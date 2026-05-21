FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN if [ ! -f package-lock.json ]; then npm install --package-lock-only; fi && npm ci --omit=dev

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src
EXPOSE 3000
CMD ["node", "src/server.js"]
