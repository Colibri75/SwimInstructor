# Stufe 1: bauen (TypeScript -> JavaScript, danach nur Produktions-Abhaengigkeiten behalten)
# Basis-Image vom AWS-Spiegel der offiziellen Docker-Images: Docker Hub drosselt anonyme Abrufe der CI-Runner (429).
FROM public.ecr.aws/docker/library/node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

# Stufe 2: schlankes Laufzeit-Image ohne Compiler und Dev-Abhaengigkeiten
FROM public.ecr.aws/docker/library/node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
# Datenverzeichnis fuer den letzten gueltigen Plan. Gehoert dem Nutzer "node", damit das Docker-Volume
# beim ersten Anlegen diese Besitzrechte uebernimmt (der restliche Container ist schreibgeschuetzt).
RUN mkdir -p /data && chown node:node /data
ENV DATA_DIR=/data
# Nie als root: das offizielle Image bringt den Nutzer "node" mit.
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/server.js"]
