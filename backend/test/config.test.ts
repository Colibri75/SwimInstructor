import { loadConfig } from "../src/config";

const validToken = "a".repeat(40);

describe("loadConfig", () => {
  it("nutzt sichere Standardwerte (nur localhost, Port 3000)", () => {
    const config = loadConfig({ API_TOKEN: validToken });

    expect(config).toMatchObject({
      env: "development",
      host: "127.0.0.1",
      port: 3000,
      apiToken: validToken,
      logLevel: "info"
    });
  });

  it("uebernimmt gesetzte Werte", () => {
    const config = loadConfig({
      API_TOKEN: validToken,
      NODE_ENV: "production",
      HOST: "0.0.0.0",
      PORT: "8080",
      LOG_LEVEL: "debug"
    });

    expect(config).toMatchObject({ env: "production", host: "0.0.0.0", port: 8080, logLevel: "debug" });
  });

  it("verweigert den Start ohne API_TOKEN", () => {
    expect(() => loadConfig({})).toThrow("API_TOKEN");
    expect(() => loadConfig({ API_TOKEN: "   " })).toThrow("API_TOKEN");
  });

  it("verlangt in Produktion einen langen Token, in Entwicklung nicht", () => {
    expect(() => loadConfig({ API_TOKEN: "kurz", NODE_ENV: "production" })).toThrow("zu kurz");
    expect(loadConfig({ API_TOKEN: "kurz", NODE_ENV: "development" }).apiToken).toBe("kurz");
  });

  it("verweigert ungueltige Ports", () => {
    for (const port of ["0", "70000", "abc", "3.5", "-1"]) {
      expect(() => loadConfig({ API_TOKEN: validToken, PORT: port })).toThrow("PORT");
    }
  });

  it("verweigert ein unbekanntes NODE_ENV", () => {
    expect(() => loadConfig({ API_TOKEN: validToken, NODE_ENV: "staging" })).toThrow("NODE_ENV");
  });

  it("schaltet das Logging im Test-Modus stumm", () => {
    expect(loadConfig({ API_TOKEN: validToken, NODE_ENV: "test" }).logLevel).toBe("silent");
  });
});
