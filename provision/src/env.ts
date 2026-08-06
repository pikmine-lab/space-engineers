/**
 * Loads the project `.env`, which holds what this repository cannot contain.
 *
 * The repository is public, so anything naming a machine or a person stays in
 * `.env`, which is git-ignored. It belongs here rather than in `~/.config`
 * because none of it is reusable outside this project. The one exception is the
 * Dokploy token, which the infra repository already reads from
 * `~/.config/dokploy/token`; `dokploy.ts` still falls back to it.
 *
 * Imported by every module that reads an environment variable, so the file is
 * loaded before anything looks at `process.env`, whatever the import order.
 */
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const ENV_FILE = resolve(import.meta.dirname, "..", "..", ".env");

if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE);

export function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is not set. Copy .env.example to .env and fill it in.`);
  return value;
}

export function optional(name: string): string {
  return process.env[name]?.trim() ?? "";
}
