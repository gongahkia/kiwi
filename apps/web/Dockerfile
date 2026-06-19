FROM node:20-alpine

WORKDIR /app

ENV HUSKY=0
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV PORT=3000

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/search build && pnpm --filter @wat/web build

EXPOSE 3000

CMD ["pnpm", "--filter", "@wat/web", "start"]
