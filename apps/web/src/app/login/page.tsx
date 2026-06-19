import { EmailLoginForm } from "@/components/email-login-form";

export default async function LoginPage({
  searchParams
}: {
  searchParams: Promise<{ check?: string; next?: string }>;
}) {
  const { check, next = "/" } = await searchParams;

  return (
    <main className="grid min-h-svh place-items-center bg-background p-6 text-foreground">
      <section className="grid w-full max-w-sm gap-4">
        <h1 className="text-2xl font-semibold">Login</h1>
        <p className="text-sm text-foreground/70">Continue to {next}</p>
        {check === "email" ? (
          <p className="rounded-md border border-input p-3 text-sm text-foreground/70">
            Check your email for a sign-in link.
          </p>
        ) : null}
        <EmailLoginForm next={next} />
      </section>
    </main>
  );
}
