# ---- Build stage ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

# ---- Runtime stage ----
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app ./
EXPOSE 3009
USER node
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3009/health || exit 1
CMD ["node", "server.js"]
