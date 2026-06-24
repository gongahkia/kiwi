FROM node:20-alpine AS runner

WORKDIR /app

ENV HUSKY=0

RUN corepack enable

COPY . .

RUN pnpm install --frozen-lockfile && pnpm --filter @wat/db build

CMD ["sh", "-c", "pnpm --filter @wat/db db:migrate && pnpm --filter @wat/db seed:dev"]
