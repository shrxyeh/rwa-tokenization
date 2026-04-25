import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center gap-3 text-center">
      <p className="text-sm font-medium text-zinc-300">Page not found</p>
      <Link href="/" className="btn-ghost text-xs">
        Back to dashboard
      </Link>
    </div>
  );
}
