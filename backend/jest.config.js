/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/test"],
  collectCoverageFrom: ["src/**/*.ts", "!src/server.ts"],
  coverageThreshold: {
    global: { lines: 80, statements: 80, functions: 80, branches: 70 },
    // Sport-Module (Triathlon-Umbau): strenger, jede neue Sportart muss vollstaendig getestet sein.
    "./src/sports/": { lines: 90, statements: 90, functions: 90, branches: 90 }
  }
};
