import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Portale Pratiche",
  description: "La tua centrale operativa ASO, BO ATPAY e reclami.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="it" data-theme="dark" suppressHydrationWarning>
      <body className="antialiased">{children}</body>
    </html>
  );
}
