import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "wat",
  description: "Layered glossary lookup"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
