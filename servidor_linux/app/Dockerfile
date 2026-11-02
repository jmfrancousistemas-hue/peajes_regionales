# Imagen de la aplicación de peajes sobre Debian 12 (bookworm)
FROM node:20-bookworm-slim

ENV NODE_ENV=production TZ=America/Bogota
WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY server.js ./
COPY public ./public

USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --retries=5 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.js"]
