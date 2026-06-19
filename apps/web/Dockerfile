FROM node:20-alpine AS deps

WORKDIR /app

ENV HUSKY=0
ENV NEXT_TELEMETRY_DISABLED=1

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/search build && pnpm --filter @wat/web build

FROM node:20-alpine AS runner

WORKDIR /app

ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV PORT=3000

COPY --from=deps /app/apps/web/.next/standalone ./
COPY --from=deps /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=deps /app/packages/ingest/seeds/manual.json ./packages/ingest/seeds/manual.json

EXPOSE 3000

WORKDIR /app/apps/web

CMD ["node", "server.js"]
