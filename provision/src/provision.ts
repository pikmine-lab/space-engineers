#!/usr/bin/env tsx
/**
 * Idempotent provisioner: reconciles Dokploy against src/specs.ts.
 *
 *   nr plan        # show the gap, change nothing
 *   nr provision   # apply
 *
 * Safe to re-run: every step reads the current state first and acts only on a
 * real difference. Nothing is ever deleted, so emptying the spec leaves the
 * server running rather than dropping a world.
 */
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { compose, findEnvironment, projects, type ComposeRef, type Project } from "./dokploy.js";
import { optional } from "./env.js";
import { SPEC } from "./specs.js";

const ROOT = resolve(import.meta.dirname, "..", "..");
const DRY_RUN = process.argv.slice(2).includes("--dry-run");

let changes = 0;
const created = (what: string) => { changes++; console.log(`  + created   ${what}`); };
const updated = (what: string, why: string) => { changes++; console.log(`  ~ updated   ${what}  (${why})`); };
const same = (what: string) => console.log(`  = unchanged ${what}`);
const planned = (what: string, action: string) => { changes++; console.log(`  ! would ${action}: ${what}`); };

/**
 * Numeric ids, one per line or comma-separated, `#` starts a comment. Order is
 * never touched.
 *
 * Comments are stripped line by line before splitting on commas, and not the
 * other way round: a comma inside a comment would otherwise cut it into pieces
 * that no longer start with `#`, and each piece would be read as an id.
 *
 * Lines are split on `\r?\n` rather than `\n` because JavaScript's `.` excludes
 * carriage returns: on a CRLF file `#.*$` cannot reach the end of a line and
 * matches nothing, so every comment survives into the ids and the whole file is
 * rejected. A Windows checkout produces exactly that.
 */
function readIds(contents: string, where: string, what: string): string[] {
  const ids = contents
    .split(/\r?\n/)
    .map((line) => line.replace(/#.*$/, ""))
    .flatMap((line) => line.split(","))
    .map((s) => s.trim())
    .filter(Boolean);

  const bad = ids.filter((id) => !/^\d+$/.test(id));
  if (bad.length) throw new Error(`${where}: not ${what}: ${bad.join(", ")}`);

  const seen = new Set<string>();
  const duplicates = ids.filter((id) => seen.size === seen.add(id).size);
  if (duplicates.length) throw new Error(`${where}: duplicates: ${[...new Set(duplicates)].join(", ")}`);

  return ids;
}

/**
 * Reads the modpack into the value of SE_MODS.
 *
 * Line order is preserved on purpose: in Space Engineers the later mod wins
 * when two of them collide, so sorting the list would silently change which
 * one does.
 */
function readModpack(): string[] {
  return readIds(readFileSync(join(ROOT, SPEC.modpackFile), "utf8"), SPEC.modpackFile, "Workshop ids");
}

/**
 * Reads the administrators from .env, which stays out of this public
 * repository. Empty is not an error: a server with no admin still runs, and
 * saying so is more useful than refusing to provision.
 */
function readAdmins(): string[] {
  const raw = optional("SE_ADMINS");
  if (!raw) {
    console.log("  ? SE_ADMINS is empty: the server will start with no administrator");
    return [];
  }
  return readIds(raw, ".env SE_ADMINS", "Steam64 ids");
}

async function ensureProject(): Promise<Project | null> {
  const existing = (await projects.all()).find((p) => p.name === SPEC.project);
  if (existing) { same(`project ${SPEC.project}`); return existing; }
  if (DRY_RUN) { planned(`project ${SPEC.project}`, "create"); return null; }
  await projects.create(SPEC.project, SPEC.projectDescription);
  created(`project ${SPEC.project}`);
  // Re-read: the create response does not carry the child collections.
  return (await projects.all()).find((p) => p.name === SPEC.project) ?? null;
}

async function ensureCompose(refs: ComposeRef[], environmentId: string) {
  // Normalised to LF: git checks this file out with CRLF on Windows, and
  // sending it as-is would make every run see a difference against what the
  // previous one stored, redeploying the server for nothing.
  const wantedFile = readFileSync(join(ROOT, SPEC.composeFile), "utf8").replace(/\r\n/g, "\n");
  const mods = readModpack();
  const admins = readAdmins();
  const wantedEnv = [
    `SE_IMAGE_TAG=${SPEC.imageTag}`,
    `SE_MODS=${mods.join(",")}`,
    `SE_ADMINS=${admins.join(",")}`,
  ].join("\n");
  const modSummary = `${mods.length ? `${mods.length} mod(s)` : "no mods"}, ${admins.length} admin(s)`;

  const ref = refs.find((c) => c.name === SPEC.service);

  if (!ref) {
    if (DRY_RUN) return planned(`compose ${SPEC.service}`, `create, upload and deploy (${SPEC.imageTag}, ${modSummary})`);
    const c = await compose.create({
      name: SPEC.service,
      description: SPEC.serviceDescription,
      environmentId,
      // Not "stack": in swarm mode published UDP ports go through the ingress
      // mesh, which rewrites the source address a game server needs to see.
      composeType: "docker-compose",
    });
    await compose.update({ composeId: c.composeId, sourceType: "raw", composeFile: wantedFile, env: wantedEnv });
    await compose.deploy(c.composeId);
    return created(`compose ${SPEC.service} (${SPEC.imageTag}, ${modSummary}, deployment queued)`);
  }

  const current = await compose.one(ref.composeId);
  const fileDrift = current.composeFile.trim() !== wantedFile.trim();
  const sourceDrift = current.sourceType !== "raw";
  // Compare as sets of lines: Dokploy may reorder or reformat.
  const norm = (s: string) => s.split("\n").map((l) => l.trim()).filter(Boolean).sort().join("\n");
  const envDrift = norm(current.env ?? "") !== norm(wantedEnv);

  // A compose can exist without ever having been deployed, typically when a
  // previous run failed between creation and deployment. Without this the
  // reconciler would call it conforming and never bring it up.
  const status = ref.composeStatus ?? "";
  const neverDeployed = !["done", "running"].includes(status);

  if (fileDrift || sourceDrift || envDrift) {
    const why = [fileDrift && "compose file", envDrift && `environment (${SPEC.imageTag}, ${modSummary})`, sourceDrift && "sourceType"]
      .filter(Boolean).join(" + ");
    if (DRY_RUN) return planned(`compose ${SPEC.service}`, `update ${why} and redeploy`);
    await compose.update({ composeId: ref.composeId, sourceType: "raw", composeFile: wantedFile, env: wantedEnv });
    await compose.deploy(ref.composeId);
    return updated(`compose ${SPEC.service}`, `${why} changed, redeployed`);
  }

  if (neverDeployed) {
    if (DRY_RUN) return planned(`compose ${SPEC.service}`, `deploy (status "${status || "unknown"}")`);
    await compose.deploy(ref.composeId);
    return updated(`compose ${SPEC.service}`, `status was "${status || "unknown"}", deployment queued`);
  }

  same(`compose ${SPEC.service} (${status}, ${SPEC.imageTag}, ${modSummary})`);
}

console.log(DRY_RUN ? "Plan (nothing will be changed)" : "Provisioning");
console.log(`\n${SPEC.project}`);

const project = await ensureProject();
if (project) {
  const env = findEnvironment(project);
  await ensureCompose(env.compose ?? [], env.environmentId);
} else {
  planned(`compose ${SPEC.service}`, "create");
}

console.log(
  changes === 0
    ? "\nServer matches the spec."
    : DRY_RUN
      ? `\n${changes} difference(s). Run \`nr provision\` to apply.`
      : `\n${changes} change(s) applied.`,
);
