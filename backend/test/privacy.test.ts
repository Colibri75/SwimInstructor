import request from "supertest";
import { createApp } from "../src/app";
import { loadConfig, PRIVACY_DEFAULTS } from "../src/config";
import { createLogger } from "../src/logger";
import { escapeHtml, renderPrivacyPolicy } from "../src/privacy/routes";
import { buildApp, TEST_TOKEN, testConfig } from "./helpers";

const contact = {
  name: "Erika Muster",
  address: "Musterstraße 1\\n12345 Musterstadt",
  email: "datenschutz@example.org",
  hoster: "Beispiel Hosting GmbH, Nürnberg (Deutschland)"
};

function appWithContact() {
  const config = { ...testConfig, privacy: contact };
  return createApp(config, createLogger(config));
}

describe("Datenschutzerklaerung", () => {
  it("ist auf Deutsch unter /datenschutz ohne Token erreichbar", async () => {
    const response = await request(buildApp()).get("/datenschutz");

    expect(response.status).toBe(200);
    expect(response.headers["content-type"]).toBe("text/html; charset=utf-8");
    expect(response.text).toContain('<html lang="de">');
    expect(response.text).toContain("Datenschutzerklärung für die App Peaksmith");
    expect(response.text).toContain("Anthropic PBC");
    expect(response.text).toContain("Art. 9 Abs. 2 lit. a DSGVO");
    expect(response.text).toContain("Art. 6 Abs. 1 lit. b DSGVO");
  });

  it("ist auf Englisch unter /privacy ohne Token erreichbar", async () => {
    const response = await request(buildApp()).get("/privacy");

    expect(response.status).toBe(200);
    expect(response.text).toContain('<html lang="en">');
    expect(response.text).toContain("Privacy Policy for the Peaksmith app");
    expect(response.text).toContain("Art. 9(2)(a) GDPR");
    expect(response.text).toContain("never sold");
  });

  it("zeigt ohne Konfiguration Platzhalter statt leerer Stellen", async () => {
    const german = await request(buildApp()).get("/datenschutz");
    const english = await request(buildApp()).get("/privacy");

    expect(german.text).toContain("[wird ergänzt]");
    expect(english.text).toContain("[to be added]");
    expect(german.text).not.toMatch(/\{\{[A-Z]+\}\}/);
    expect(english.text).not.toMatch(/\{\{[A-Z]+\}\}/);
  });

  it("setzt Verantwortlichen, Anschrift, E-Mail und Hoster aus der Konfiguration ein", async () => {
    const response = await request(appWithContact()).get("/datenschutz");

    expect(response.text).toContain("Erika Muster<br>Musterstraße 1<br>12345 Musterstadt");
    expect(response.text).toContain('<a href="mailto:datenschutz@example.org">datenschutz@example.org</a>');
    expect(response.text).toContain("Beispiel Hosting GmbH, Nürnberg (Deutschland)");
    expect(response.text).not.toContain("[wird ergänzt]");
    const english = await request(appWithContact()).get("/privacy");
    expect(english.text).not.toContain("[to be added]");
  });

  it("laedt nichts von fremden Servern und erlaubt keine Skripte", async () => {
    const response = await request(buildApp()).get("/datenschutz");

    expect(response.headers["content-security-policy"]).toContain("default-src 'none'");
    expect(response.text).not.toMatch(/<script|<link|<img|src=/i);
    expect(response.headers["set-cookie"]).toBeUndefined();
  });

  it("maskiert Angaben aus der Konfiguration", () => {
    const html = renderPrivacyPolicy("de", { ...contact, name: '<script>alert("x")</script>' });

    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;");
    expect(escapeHtml("a & 'b'")).toBe("a &amp; &#39;b&#39;");
  });

  it("nimmt ohne Umgebungsvariablen den Verantwortlichen aus dem Code, den Hoster nicht", async () => {
    const config = loadConfig({ API_TOKEN: TEST_TOKEN });
    expect(config.privacy).toEqual({ ...PRIVACY_DEFAULTS, hoster: undefined });

    const response = await request(createApp(config, createLogger(config))).get("/datenschutz");
    expect(response.text).toContain("Steffen Kellner<br>Alfelder Weg 55, 90482 Nürnberg, Deutschland");
    expect(response.text).toContain("mailto:steffen.kellner91@gmail.com");
    expect(response.text).toContain("bei [wird ergänzt]");
  });

  it("liest die Angaben aus den Umgebungsvariablen", () => {
    const config = loadConfig({
      API_TOKEN: TEST_TOKEN,
      PRIVACY_CONTACT_NAME: " Erika Muster ",
      PRIVACY_CONTACT_ADDRESS: "Musterstraße 1",
      PRIVACY_CONTACT_EMAIL: "datenschutz@example.org",
      PRIVACY_HOSTER: ""
    });

    expect(config.privacy).toEqual({ name: "Erika Muster", address: "Musterstraße 1", email: "datenschutz@example.org", hoster: undefined });
  });

  it("bleibt unter /v1 hinter dem Token", async () => {
    const response = await request(buildApp()).get("/v1/privacy");

    expect(response.status).toBe(401);
  });
});
