# Receipt Tracker

A mobile-first PWA for splitting receipts and tracking who owes you.
Next.js (App Router) + Supabase (Postgres, Auth, Storage) + Vercel — all serverless, all free-tier.

## 1. Create a Supabase project

1. Go to https://supabase.com, create a free account, then **New Project**.
2. Once it's provisioned, open **SQL Editor** and run the contents of `supabase/schema.sql`.
   This creates the tables, row-level security policies, and the private `receipts` storage
   bucket used for photo uploads.
3. In **Authentication -> Providers**, Email is enabled by default — that's all this app
   uses (magic link, no password).
4. In **Authentication -> URL Configuration**, add your local and deployed URLs to
   "Redirect URLs", e.g. `http://localhost:3000/auth/callback` and
   `https://your-app.vercel.app/auth/callback`.
5. Grab your keys from **Project Settings -> API**: the Project URL and the `anon` public key.

## 2. Run it locally

```bash
cp .env.local.example .env.local   # then paste in your Supabase URL + anon key
npm install
npm run dev
```

Open http://localhost:3000, sign in with your email (you'll get a magic link), and start adding
receipts. On an iPhone, open the deployed URL in Safari and use **Share -> Add to Home Screen**
to install it as a standalone app.

## 3. Deploy to Vercel (free)

1. Push this project to a GitHub repo.
2. Go to https://vercel.com, sign in with GitHub, and **Import Project** from that repo.
3. Add the two environment variables from `.env.local` in the Vercel project settings
   (Settings -> Environment Variables).
4. Deploy. Vercel gives you a `.vercel.app` URL automatically — add that URL's
   `/auth/callback` path to Supabase's redirect URL list (step 1.4 above), or magic links
   won't be able to log you back in on the deployed site.

## Notes

- **Icons**: `public/manifest.json` references `/icons/icon-192.png` and `/icons/icon-512.png`,
  which aren't included — drop in your own square PNGs (or generate them from a favicon tool)
  before deploying so the home-screen icon looks right.
- **Storage**: receipt photos are compressed client-side before upload and stored in a private
  Supabase bucket, scoped per-user, with signed URLs generated on read (1-hour expiry).
- **Auth**: this uses Supabase's passwordless email magic link — no separate password to manage.
- **Split math** lives in `lib/split.ts` — the same logic used in the original prototype
  (proportional or equal tax/tip allocation, FIFO payment allocation across receipts).
