FROM node:20-alpine AS deps

WORKDIR /app

ENV HUSKY=0

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/slack build

FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3001
ENV SLACK_HTTP_MODE=true

COPY --from=deps /app/dist ./apps/slack/dist
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/slack/node_modules ./apps/slack/node_modules
COPY --from=deps /app/apps/slack/package.json ./apps/slack/package.json

WORKDIR /app/apps/slack

EXPOSE 3001

CMD ["node", "dist/server.js"]
