export default function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse bg-[#EFEBDD] rounded-lg ${className}`} />;
}
