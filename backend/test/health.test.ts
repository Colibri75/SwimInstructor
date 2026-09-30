import request from "supertest";
import { buildApp } from "./helpers";

describe("GET /health", () => {
  it("antwortet ohne Token mit 200 und Status ok", async () => {
    const response = await request(buildApp()).get("/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("ok");
    expect(typeof response.body.uptimeSeconds).toBe("number");
  });

  it("verraet nicht, dass es Express ist", async () => {
    const response = await request(buildApp()).get("/health");

    expect(response.headers["x-powered-by"]).toBeUndefined();
  });
});

describe("unbekannte Routen", () => {
  it("liefern 404 als JSON", async () => {
    const response = await request(buildApp()).get("/gibt-es-nicht");

    expect(response.status).toBe(404);
    expect(response.body).toEqual({ error: "not_found" });
  });

  it("unter /v1 verlangen zuerst den Token (kein Routen-Scan ohne Auth)", async () => {
    const response = await request(buildApp()).get("/v1/gibt-es-nicht");

    expect(response.status).toBe(401);
  });
});
