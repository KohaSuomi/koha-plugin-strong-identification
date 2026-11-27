# Plan: Suomi.fi OIDC Self-Registration (in this repository)

Target Koha version 26.05.04.000

## 1. Goal

Implement a self-registration flow where a user verifies their identity with
Suomi.fi-tunnistus OIDC, completes a registration form, and creates a patron
directly in Koha with the temporary category `HAKEMUS` ("Vahva tunnistautuja").
Staff complete the registration when the user collects their card by changing
the category. Temporary accounts expire after two weeks and are removed by the plugin's own
cleanup script, not by Koha core `cleanup_database.pl`. No Koha session is
created.

## 2. Adjustments from the original plan

1. **Repository**: Keep this repository name as-is. Implement the
   self-registration plugin inside it. The plugin package can remain
   `Koha::Plugin::Fi::KohaSuomi::StrongIdentification` or add an OIDC package if
   the existing endpoint must stay. No new repository is required.
2. **Koha version**: Active dev is Koha 26.05.04.000. Set
   `minimum_version => '26.05'` and validate on ks26.
3. **No Apache standalone page**: `UseKohaPlugins` was removed in modern Koha.
   Serve the form through plugin REST routes:
   - `GET /api/v1/contrib/kohasuomi/suomifi/register_start`
   - `GET /api/v1/contrib/kohasuomi/suomifi/register_callback` (renders HTML)
   - `POST /api/v1/contrib/kohasuomi/suomifi/register_submit`
   - `GET /api/v1/contrib/kohasuomi/suomifi/logout`
   - `GET /api/v1/contrib/kohasuomi/suomifi/post_logout`
   Plugin contrib routes are public when `x-koha-authorization` is omitted.
4. **Templates in REST controllers**: Render Template Toolkit directly from
   files under the plugin bundle directory (`mbf_dir()`).
5. **State/CSRF storage**: Do not create a Koha session. Use a short-lived
   signed cookie (`suomifi_state`) with HMAC validation.
6. **Static assets**: Use plugin `static_routes` or inline CSS/JS.
7. **OIDC libraries**: Use `Crypt::JWT` for RS256 verification against Suomi.fi
   JWKS and `Mojo::UserAgent` for HTTP calls.
8. **Configuration persistence**: Use `store_data`/`retrieve_data`; store one JSON
   object under key `config`, optionally a separate `logo` key.

No Koha core changes are required.

## 2.1 Meeting decisions (working group, 5.11.2026)

- Create the patron directly with category `HAKEMUS` ("Vahva tunnistautuja"),
  retention two weeks, cleaned by the plugin's own cleanup script.
- Use sysprefs:
  - `PatronSelfRegistrationDefaultCategory`
  - `PatronSelfRegistrationExpireTemporaryAccountsDelay`
- Initially only SSN-holding (hetulliset) customers via Suomi.fi; non-SSN later.
- Duplicate check by SSN; `PatronDuplicateMatchingAddFields` not needed.
- Add all given names from Suomi.fi to `firstname`.
- Add a reservation-number field, optional.
- Ask messaging preferences on the form and set them automatically.
- Ask for guarantor's possible card number and verify it with PIN.
- Add a card-pickup reminder notice template and cron based on account creation
  date.
- Add JavaScript that disables the card number for `HAKEMUS` category.
- Prevent lending etc. for `HAKEMUS` via circulation and fee rules.
- Child/guardian registration is out of scope for the first phase.

## 3. Repository strategy

Proceed in this repository:

- `koha-plugin-strong-identification`

Use the existing plugin as scaffold. If its current endpoint must remain
available, add the self-registration code alongside it. Otherwise transform the
plugin.

## 4. Package and metadata

- Namespace: `kohasuomi` (`api_namespace` returns `kohasuomi`)
- Metadata:
  - name: `Suomi.fi OIDC self-registration`
  - author: `Emmi Takkinen ja Johanna Räisä`
  - minimum_version: `26.05`
  - version: `1.0.0`

## 5. File structure

```
Koha/Plugin/Fi/KohaSuomi/StrongIdentification/
├── StrongIdentification.pm (or OIDC.pm)
├── Controllers/
│   └── Register.pm
├── SuomifiClient.pm
├── Templates/
│   ├── configure.tt
│   ├── register.tt
│   └── register-confirmation.tt
├── public/
│   ├── index.html
│   ├── register.css
│   └── register.js
├── etc/
│   └── apache-suomifi-register.conf
├── cronjobs/
│   └── cleanup_expired_registrations.pl
└── openapi.yaml
```

## 6. Public entry point and routing

The public-facing UI is served by Apache (and exposed through HAProxy), while
the plugin REST API remains the backend. Apache serves the static registration
page and proxies API requests to Koha/Plack.

Public entry point:

- Apache/HAProxy URL: `/self-register` (or configured alias)
- The page links to `GET /api/v1/contrib/kohasuomi/suomifi/register_start`
- `register_start` redirects to Suomi.fi, then back to
  `register_callback`, which renders the form

No Koha OPAC is required.

On Finna, provide a link to this entry point. All subsequent registration
steps are handled by the plugin flow.

`openapi.yaml` defines five routes. Omit `x-koha-authorization` on all of them
so plugin auth logic allows anonymous access:

- `GET /register_start`
- `GET /register_callback`
- `POST /register_submit`
- `GET /logout`
- `GET /post_logout`

The controller must validate CSRF on state-changing or user-specific steps.

## 6.1 Frontend, Apache, and HAProxy

- Add a small frontend (HTML/CSS/JS) under `public/` or `htdocs/`.
- Add `etc/apache-suomifi-register.conf` to alias the frontend and proxy the
  API if needed.
- Configure HAProxy to route:
  - `/self-register*` and static assets to Apache
  - `/api/v1/contrib/kohasuomi/suomifi/*` to Koha/Plack
- Keep all dynamic OIDC logic in the plugin REST routes; the frontend only
  starts the flow and displays the returned pages.

## 7. OIDC client (`SuomifiClient.pm`)
Implement:

- `discover()` — fetch `well_known_url`, cache endpoints.
- `authorize_url($config, $state, $nonce)` — build Suomi.fi authorize URL.
- `exchange_code($config, $code)` — POST to token endpoint.
- `verify_id_token($config, $id_token, $nonce)` — Crypt::JWT verification:
  - `kid_keys` from JWKS
  - `verify_iss => $issuer`
  - `verify_aud => $client_id`
  - `verify_exp => 1`
  - extract nonce and compare.
- `claims($id_token)` — return hash of claims.
- `end_session_url($config, $id_token)` — build front-channel logout URL.
- `required_acr_ok($claims, $required_acr)`.

Cache JWKS with a short TTL.

## 8. Registration flow

### register_start
- Generate `state` and `nonce`.
- Store both in a signed cookie.
- Redirect to Suomi.fi authorize URL.

### register_callback
- Validate `state` against cookie.
- Exchange code.
- Verify ID token and ACR.
- Extract claims.
- Load config and `form_fields`.
- Pre-fill `oidc:`-sourced fields using `attribute_mapping`.
- Render `register.tt` as HTML.

### register_submit
- Validate CSRF/state.
- Validate mandatory fields, SSN duplicate check, email uniqueness, branch
  whitelist, age limits, GDPR consent, optional password policy.
- Build patron data hash keyed by `borrower_field`.
- Set category to `HAKEMUS`.
- Add messaging preferences from the form.
- Store guarantor card number if provided and verified with PIN.
- Create patron directly with `Koha::Patron->new(...)->store()`.
- Render confirmation with application reference and logout countdown.

### logout
- Clear local cookie state.
- Redirect browser to Suomi.fi `end_session_endpoint` with
  `post_logout_redirect_uri` = `home_url`.

### post_logout
- Optional landing page if Suomi.fi requires a registered redirect URI.

## 9. Mutable form configuration

- `form_fields` is a JSON array in config.
- Template renders fields dynamically by `type`, `readonly`, `required`,
  `options`.
- Submit maps values by `borrower_field`.
- `attribute_mapping` maps OIDC claims to borrower fields for pre-fill.
- Configure page validates JSON before saving.

## 10. eIDAS handling

Suomi.fi documentation confirms that eIDAS-identified users do not create a
single sign-on session and do not retrieve data from the Finnish population
register. Their data contains first name, last name, PID, and date of birth.

- If no PID claim and `eidas_allow` is false: reject.
- If allowed: flag application, use limited claim set (no SSN), apply
  defaults.

## 10.1 Duplicate check and SSN handling

- Investigate whether SSN can be fetched directly from Suomi.fi.
- Check for an existing patron by SSN before creating a new one.
- If no SSN is available, reject or defer according to `eidas_allow`.

## 10.2 Messaging preferences and guarantor

- Ask messaging preferences on the form and set them automatically.
- Ask for guarantor's possible card number and verify it with PIN.

## 10.3 No card number at registration

No card number is assigned during self-registration. Staff assign the card
number when the user collects the card. Because the patron has no card number,
they cannot log in to Finna until registration is completed. The form and
category handling must ensure `HAKEMUS` patrons do not receive a card number.

## 10.4 Card pickup notice and staff completion

- Add a new notice template for card pickup reminder.
- Add a cron job to send the reminder based on account creation date.
- Add JavaScript that disables the card number for `HAKEMUS` category.
- Prevent lending and related actions for `HAKEMUS` via circulation and fee
  rules.

## 11. Logout UX

- Confirmation page shows one prominent button:
  `Palaa takaisin verkkokirjastoon`.
- JavaScript countdown using `logout_redirect_seconds`.
- Message: `Rekisteröityminen on valmis. Sinut ohjataan takaisin verkkokirjastoon N sekunnin kuluttua.`
- Clicking cancels countdown and redirects immediately.
- Soft reload re-reads server-rendered target.

## 12. Implementation phases

1. **Scaffold**
   - Add self-registration modules/templates under the existing plugin.
   - Update metadata if needed: `minimum_version => '26.05'`, version bump.
   - Add or update OpenAPI spec for the five self-registration routes.
   - Keep `deploy.sh` and `create-symlinks.sh` working.
2. **Configuration layer**
   - `get_config`/`set_config`.
   - Configure template with scalar fields and JSON editors.
   - Logo upload as base64.
3. **OIDC client**
   - Discovery, authorize URL, token exchange, JWT verification, logout URL.
4. **register_start and register_callback**
   - State/nonce cookie.
   - Form rendering and pre-fill.
5. **register_submit**
   - Validation and direct patron creation.
   - Confirmation page.
6. **Logout**
   - `/logout`, `/post_logout`, countdown.
7. **Cleanup script**
   - Plugin cron job to remove expired `HAKEMUS` patrons.
8. **Mutable form editor**
   - JSON validation and preview.
9. **Tests**
   - JWT verification unit tests.
   - Claim mapping and form/borrower mapping.
   - Integration tests against mock IdP (Koha `t/lib/IdP/ExternalIdP.pm`).
9. **Frontend and Apache/HAProxy**
   - Static UI and Apache alias.
   - HAProxy routing.

## 13. Testing notes

- Run targeted tests only, using existing Koha test infrastructure.
- Do not create test environments or connect to external services.
- Mock Suomi.fi endpoints in tests.
- Suomi.fi test environment: https://testipalvelu.apro.tunnistus.fi/
- Verify patron creation and cleanup behavior.

## 14. Risks

- Suomi.fi OIDC endpoints and claim names must be confirmed against official
  documentation.
- `Crypt::JWT` JWKS handling must be tested with real Suomi.fi keys.
- Public route security depends on CSRF and state validation; review carefully.
- Template rendering in REST context is non-standard; keep HTML simple.
- eIDAS flows may require different default categories and validation.

## 15. Implementation steps (what to do in this repo)

### Phase 1: Scaffold (no rename)
- [ ] Keep repository and package names as-is.
- [ ] Add self-registration modules/templates under the existing plugin.
- [ ] Update metadata if needed: `minimum_version => '26.05'`, version bump.
- [ ] Add or update OpenAPI spec for the five self-registration routes.
- [ ] Keep `deploy.sh` and `create-symlinks.sh` working.

### Phase 2: Configuration layer
- [ ] Implement `get_config`/`set_config`.
- [ ] Add `configure` method rendering `Templates/configure.tt`.
- [ ] Add settings listed in section 4.6 of the original plan.
- [ ] Add base64 logo upload handling.

### Phase 3: OIDC client
- [ ] Create `SuomifiClient.pm`.
- [ ] Implement discovery, authorize URL, token exchange, JWT verification,
      claim extraction, ACR enforcement, logout URL.

### Phase 4: Public routes and controller
- [ ] Create `Controllers/Register.pm`.
- [ ] Implement `register_start`, `register_callback`, `register_submit`,
      `logout`, `post_logout`.
- [ ] Omit `x-koha-authorization` in `openapi.yaml` for anonymous access.
- [ ] Add signed-cookie state/nonce handling.

### Phase 5: Form and templates
- [ ] Create `register.tt` with dynamic `form_fields` rendering.
- [ ] Create `register-confirmation.tt` with countdown and logout button.
- [ ] Create `configure.tt` with JSON editors and logo upload.
- [ ] Implement pre-fill from `attribute_mapping`.

### Phase 6: Patron creation
- [ ] Validate form and SSN duplicate check.
- [ ] Build patron data by `borrower_field`.
- [ ] Set category to `HAKEMUS`.
- [ ] Add messaging preferences and optional guarantor verification.
- [ ] Create patron directly with `Koha::Patron->new(...)->store()`.

### Phase 7: Logout UX
- [ ] Implement `/logout` redirect to Suomi.fi end_session.
- [ ] Implement `/post_logout` landing page.
- [ ] Add JavaScript countdown to confirmation page.

### Phase 7b: Cleanup script
- [ ] Create `cronjobs/cleanup_expired_registrations.pl`.
- [ ] Remove expired `HAKEMUS` patrons based on creation date and retention.

### Phase 8: eIDAS handling and login restriction
- [ ] Reject when no PID and `eidas_allow` is false.
- [ ] Flag and limit claims when allowed.
- [ ] Ensure no card number is assigned during self-registration.

### Phase 9: Tests
- [ ] Add unit tests for JWT verification, claim mapping, form/borrower mapping.
- [ ] Add integration tests against a mock IdP.
- [ ] Verify pending modification creation and approval.

### Phase 10: Documentation and packaging
- [ ] Update README.
- [ ] Run deploy.sh and verify KPZ.
- [ ] Install via symlinks and test on ks26.

### Phase 11: Frontend and Apache/HAProxy
- [ ] Create static UI under `public/`.
- [ ] Add `etc/apache-suomifi-register.conf`.
- [ ] Configure HAProxy routes for UI and API.

## 16. Open decisions

1. Target ks25 in addition to ks26?
2. Exact Suomi.fi `acr_values`, scopes, and claim OIDs.
3. Whether `post_logout_redirect_uri` can be Finna directly or must be the
   plugin's `/post_logout`.
4. Default `preregistration_category` and branch validation rules.
5. Whether to keep the existing strong-identification endpoint or replace it.
