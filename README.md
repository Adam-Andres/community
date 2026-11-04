# Community

A Flutter-web PWA where community members share profiles (phone, email), issues, tasks (assigned to a member) and comments on tasks.
It's hosted on GitHub Pages and uses Firebase (Auth + Firestore) as the backend, so data syncs across devices.

## How the rules are enforced

All ownership rules are enforced server-side in [`firestore.rules`](firestore.rules), not only in the UI:

| Data | Read | Create | Update / delete |
|---|---|---|---|
| `members/{uid}` | any signed-in member | only that uid | only that uid (no delete) |
| `issues` | any signed-in member | any member (as owner) | owner only |
| `tasks` | any signed-in member | any member (as owner), assignee must be a member | owner (creator) only |
| `tasks/{id}/comments` | any signed-in member | any member (as owner) | author only |

Firebase Auth makes login emails unique and handles passwords.

## Setup
1. Firebase console → create a project → **Authentication** → enable **Email/Password**.
2. **Firestore Database** → create the database → **Rules** tab → paste `firestore.rules` → Publish.
3. Project settings → add a **Web app** → copy its config into `lib/firebase_options.dart`.
4. Authentication → Settings → **Authorized domains** → add `<your-github-user>.github.io`.
5. GitHub: push to `main`, then Settings → Pages → Source: **GitHub Actions**. The workflow builds and deploys to `https://<user>.github.io/<repo>/`.

Local run: `flutter run -d chrome`.
