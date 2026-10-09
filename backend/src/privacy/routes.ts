import { Express, Response } from "express";
import { PrivacyContact } from "../config";
import { POLICY_DE, POLICY_EN, PRIVACY_POLICY_DATE } from "./texts";

/**
 * Die Datenschutzerklaerung als schlichte HTML-Seite: `GET /datenschutz` (Deutsch) und `GET /privacy` (Englisch).
 * Oeffentlich und ohne Token (App Store und die App verlinken darauf), ohne Cookies und ohne fremde Ressourcen.
 */
export type PrivacyLanguage = "de" | "en";

const MISSING: Record<PrivacyLanguage, string> = { de: "[wird ergänzt]", en: "[to be added]" };
const TITLE: Record<PrivacyLanguage, string> = { de: "Datenschutzerklärung – PeakSmith", en: "Privacy Policy – PeakSmith" };

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function multiline(value: string): string {
  return value
    .split(/\\n|\n/)
    .map((line) => escapeHtml(line.trim()))
    .filter((line) => line !== "")
    .join("<br>");
}

/** Die ganze Seite mit den Angaben aus der Konfiguration; fehlende stehen als "[wird ergänzt]" darin. */
export function renderPrivacyPolicy(language: PrivacyLanguage, contact: PrivacyContact): string {
  const missing = MISSING[language];
  const values: Record<string, string> = {
    NAME: contact.name !== undefined ? escapeHtml(contact.name) : missing,
    ANSCHRIFT: contact.address !== undefined ? multiline(contact.address) : missing,
    EMAIL: contact.email !== undefined ? `<a href="mailto:${escapeHtml(contact.email)}">${escapeHtml(contact.email)}</a>` : missing,
    HOSTER: contact.hoster !== undefined ? escapeHtml(contact.hoster) : missing,
    STAND: PRIVACY_POLICY_DATE[language]
  };
  const body = (language === "de" ? POLICY_DE : POLICY_EN).replace(/\{\{([A-Z]+)\}\}/g, (match, key: string) => values[key] ?? match);
  return `<!doctype html>
<html lang="${language}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TITLE[language]}</title>
<style>
  :root { color-scheme: light dark; --text: #1d1d1f; --muted: #6e6e73; --bg: #ffffff; --link: #c2410c; }
  @media (prefers-color-scheme: dark) { :root { --text: #f5f5f7; --muted: #a1a1a6; --bg: #111114; --link: #fb923c; } }
  body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 1.8rem; line-height: 1.25; margin: 0 0 8px; }
  h2 { font-size: 1.25rem; margin: 32px 0 8px; }
  h3 { font-size: 1.05rem; margin: 20px 0 6px; }
  ul { padding-left: 1.2rem; }
  li { margin: 6px 0; }
  a { color: var(--link); }
  .meta { color: var(--muted); font-size: 0.9rem; }
</style>
</head>
<body>
<main>
${body.trim()}
</main>
</body>
</html>
`;
}

function send(res: Response, html: string): void {
  res
    .status(200)
    .set({
      "Content-Type": "text/html; charset=utf-8",
      // Nur eingebettete Styles, keine Skripte, nichts von fremden Servern.
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "Cache-Control": "public, max-age=3600"
    })
    .send(html);
}

/** Haengt `/datenschutz` und `/privacy` ein (ausserhalb von /v1, also ohne Token). Die Seiten entstehen einmal beim Start. */
export function registerPrivacyRoutes(app: Express, contact: PrivacyContact): void {
  const pages: Record<PrivacyLanguage, string> = { de: renderPrivacyPolicy("de", contact), en: renderPrivacyPolicy("en", contact) };
  app.get("/datenschutz", (_req, res) => send(res, pages.de));
  app.get("/privacy", (_req, res) => send(res, pages.en));
}
