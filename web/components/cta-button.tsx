"use client";
import { trackEvent } from "@/lib/posthog";

interface CTAButtonProps {
  href: string;
  children: React.ReactNode;
  className?: string;
  page?: string;
  variant?: "primary" | "secondary";
}

export function CTAButton({
  href,
  children,
  className = "",
  page,
  variant = "primary",
}: CTAButtonProps) {
  const slug =
    page ?? (typeof window !== "undefined" ? window.location.pathname : "");

  const baseStyles =
    variant === "primary"
      ? "bg-white text-blue-600 hover:bg-blue-50 shadow-lg"
      : "bg-blue-500 hover:bg-blue-600 text-white";

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={`inline-block font-semibold px-8 py-3.5 rounded-lg transition ${baseStyles} ${className}`}
      onClick={() =>
        trackEvent("cta_click", {
          page: slug,
          href,
          text: typeof children === "string" ? children : undefined,
        })
      }
    >
      {children}
    </a>
  );
}
