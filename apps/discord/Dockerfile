FROM node:20-alpine AS deps

WORKDIR /app

ENV HUSKY=0

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/discord build

FROM node:20-alpine AS runner

WORKDIR /app/apps/discord

ENV NODE_ENV=production
ENV PORT=3002

COPY --from=deps /app/node_modules /app/node_modules
COPY --from=deps /app/apps/discord/node_modules ./node_modules
COPY --from=deps /app/apps/discord/dist ./dist
COPY --from=deps /app/apps/discord/package.json ./package.json

EXPOSE 3002

CMD ["node", "dist/server.js"]
