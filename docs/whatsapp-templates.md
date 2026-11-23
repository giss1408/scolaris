# WhatsApp: the template to submit to Meta

Scolaris sends WhatsApp messages through the **official WhatsApp Business Cloud API** only (never an unofficial WhatsApp Web automation: it risks the number being banned).
Outside the 24-hour customer window only **approved templates** can be sent. One utility template covers every notice (absence, cancelled course, replacement teacher, payment reminder).

| | |
|---|---|
| Name | `scolaris_information` (SCO_WA_TEMPLATE) |
| Category | UTILITY |
| Language | French (`fr`) (SCO_WA_LANGUAGE) |
| Body | `Bonjour {{1}}, message de l'école {{2}} : {{3}} Merci de votre confiance.` |
| Variables | {{1}} parent's name, {{2}} school's name, {{3}} the notice (one line, at most 600 characters) |
| Examples for the review | {{1}} Kouassi Paul, {{2}} Groupe Scolaire Les Palmiers, {{3}} Fanta TRAORE a été noté(e) absent(e) au cours de Mathématiques (08:00-09:00) le 23/11. |

Variables are cleaned before sending (Meta rejects newlines, tabs and runs of spaces in a variable). A parent is only messaged when she **agreed to WhatsApp** (opt-in recorded at enrolment) and the school's director switched **automatic messages** on (Profil). Messages go out between 07:00 and 20:00, never on Sunday; a message that cannot be sent is listed for the staff to phone instead.

## Switching it on (staging, then production)
1. Create the Meta app, the WhatsApp Business account and a phone number; submit the template above; wait for approval.
2. Set in `.env.platform`: `SCO_WA_MODE=live`, `SCO_WA_TOKEN` (a system-user token, never a personal one), `SCO_WA_PHONE_NUMBER_ID`, `SCO_WA_APP_SECRET` (verifies the webhook signature), `SCO_WA_VERIFY_TOKEN` (any long random string). The service **refuses to start** in `live` mode if one of them is missing.
3. Register the webhook in the Meta console: `https://scolaris-api.<domain>/webhooks/whatsapp`, with the verify token, subscribed to `messages` (delivery statuses). The route is public and verifies `X-Hub-Signature-256` over the raw body.
4. Send to a test number first (`SCO_ALLOW_TEST_NUMBERS`), watch Profil > Messages aux familles (sent / delivered / read / failed), then switch the first school on.

Never log or paste the token. Rotate it by changing `SCO_WA_TOKEN` and restarting; nothing else depends on it.
