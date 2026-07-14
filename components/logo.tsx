import { Flame } from "lucide-react";
import Link from "next/link";

export function Logo({ dark = false }: { dark?: boolean }) {
  return (
    <Link href="/" className={`brand ${dark ? "brand-dark" : ""}`}>
      <span className="brand-mark"><Flame size={24} strokeWidth={2.4} /></span>
      <span className="brand-copy">
        <strong>ACADEMIA</strong>
        <b>BOMBEIRO CIVIL</b>
      </span>
    </Link>
  );
}
