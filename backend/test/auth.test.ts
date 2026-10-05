import request from "supertest";
import { buildApp, TEST_TOKEN } from "./helpers";

describe("Token-Auth unter /v1", () => {
  const app = buildApp();

  it("lehnt Requests ohne Authorization-Header mit 401 ab", async () => {
    const response = await request(app).get("/v1/status");

    expect(response.status).toBe(401);
    expect(response.body).toEqual({ error: "unauthorized" });
    expect(response.headers["www-authenticate"]).toBe("Bearer");
  });

  it("lehnt einen falschen Token mit 401 ab", async () => {
    const response = await request(app).get("/v1/status").set("Authorization", "Bearer falsch");

    expect(response.status).toBe(401);
  });

  it("lehnt einen Token mit richtigem Praefix, aber anderer Laenge ab", async () => {
    const response = await request(app).get("/v1/status").set("Authorization", `Bearer ${TEST_TOKEN}x`);

    expect(response.status).toBe(401);
  });

  it("lehnt ein anderes Schema (Basic) und den nackten Token ab", async () => {
    const basic = await request(app).get("/v1/status").set("Authorization", `Basic ${TEST_TOKEN}`);
    const bare = await request(app).get("/v1/status").set("Authorization", TEST_TOKEN);

    expect(basic.status).toBe(401);
    expect(bare.status).toBe(401);
  });

  it("lehnt einen leeren Bearer-Wert ab", async () => {
    const response = await request(app).get("/v1/status").set("Authorization", "Bearer ");

    expect(response.status).toBe(401);
  });

  it("laesst den richtigen Token mit 200 durch", async () => {
    const response = await request(app).get("/v1/status").set("Authorization", `Bearer ${TEST_TOKEN}`);

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: "authenticated", user: "owner" });
  });

  it("akzeptiert das Schema unabhaengig von der Gross-/Kleinschreibung", async () => {
    const response = await request(app).get("/v1/status").set("Authorization", `bearer ${TEST_TOKEN}`);

    expect(response.status).toBe(200);
  });

  it("prueft den Token vor dem Body-Parsing (kaputtes JSON ohne Token ergibt 401, nicht 400)", async () => {
    const response = await request(app)
      .post("/v1/status")
      .set("Content-Type", "application/json")
      .send("{kaputt");

    expect(response.status).toBe(401);
  });
});
