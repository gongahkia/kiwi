"use client";

import { signIn } from "next-auth/react";
import { type FormEvent, useState } from "react";

import { Button } from "@/components/ui/button";

interface EmailLoginFormProps {
  next: string;
}

type FormState = "idle" | "sending" | "sent" | "error";

export function EmailLoginForm({ next }: EmailLoginFormProps) {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<FormState>("idle");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setState("sending");
    const result = await signIn("email", {
      callbackUrl: next,
      email,
      redirect: false
    });
    setState(result?.error ? "error" : "sent");
  }

  return (
    <form className="grid gap-3" onSubmit={submit}>
      <label className="grid gap-2 text-sm font-medium">
        Email
        <input
          autoComplete="email"
          autoFocus
          className="h-11 rounded-md border border-input bg-background px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-ring"
          onChange={(event) => setEmail(event.target.value)}
          required
          type="email"
          value={email}
        />
      </label>
      <Button disabled={state === "sending"} type="submit">
        {state === "sending" ? "Sending..." : "Send magic link"}
      </Button>
      {state === "sent" ? (
        <p className="text-sm text-foreground/70">Check your email for a sign-in link.</p>
      ) : null}
      {state === "error" ? (
        <p className="text-sm text-destructive">Could not send sign-in link.</p>
      ) : null}
    </form>
  );
}
