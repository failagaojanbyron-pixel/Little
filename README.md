# Our Little World — cloud edition

This folder contains the Supabase-backed version. The original standalone app is preserved one level up as `our-little-world-standalone-backup.html`.

## Connect the backend

1. Create a project at https://supabase.com.
2. Open **SQL Editor**, paste all of `supabase-schema.sql`, and run it once.
3. Open **Project Settings → API** and copy the project URL and anon/publishable key into `config.js`.
4. In **Authentication → URL Configuration**, add the URL where you will host this app.
5. Serve this folder through a local web server for testing. Opening `index.html` directly also works in most browsers, but a local server is more reliable.
6. Deploy the folder to any static host such as Netlify, Cloudflare Pages, or Vercel.

## How sharing works

The first person creates a shared space after registering. The app displays an eight-character invite code. The second person registers separately and joins with that code. Database and Storage policies restrict every record and original photo to those two authenticated accounts.

## Privacy notes

- The Supabase anon/publishable key is intended for browser use. Never put a service-role key in `config.js`.
- The photo bucket is private and the app creates temporary signed image links.
- Email confirmation is enabled by default in many Supabase projects. A new user may need to confirm their email before signing in.
- Use a production HTTPS host before entering real private information.
