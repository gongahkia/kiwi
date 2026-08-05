FROM node:20-alpine AS runner

WORKDIR /app

ENV HUSKY=0

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/db build

CMD ["pnpm", "db:deploy"]
