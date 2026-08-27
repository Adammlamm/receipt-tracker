#!/bin/bash
set -e
echo "Applying: Next.js security patch (14.2.5 -> 14.2.35, fixes CVE-2025-29927)..."

mkdir -p $(dirname 'package.json')
cat > 'package.json' << 'FILEEOF'
{
  "name": "receipt-tracker",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@supabase/ssr": "^0.5.2",
    "@supabase/supabase-js": "^2.45.4",
    "lucide-react": "^0.383.0",
    "next": "^14.2.35",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.15.4"
  },
  "devDependencies": {
    "@types/node": "^20.14.2",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.38",
    "tailwindcss": "^3.4.4",
    "typescript": "^5.5.2",
    "vitest": "^4.1.11"
  }
}
FILEEOF

echo "package.json updated. Installing the new Next.js version..."
npm install
echo "Running tests to confirm nothing broke..."
npm test
echo "Done. Now run: git add . && git commit -m \"Upgrade Next.js to 14.2.35 (security patch)\" && git push"
