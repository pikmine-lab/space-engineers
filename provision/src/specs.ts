/**
 * Declarative description of the Space Engineers server.
 *
 * This file is the source of truth. `provision.ts` reconciles Dokploy against
 * it and never the other way around, so anything changed by hand in the
 * dashboard is put back on the next run.
 */

export type Spec = {
  /** Dokploy project, kept separate from `shared` so nothing here can disturb the base services. */
  project: string;
  projectDescription: string;
  /** Compose service name inside that project. */
  service: string;
  serviceDescription: string;
  /** Compose file, relative to the repository root. */
  composeFile: string;
  /** Modpack file, relative to the repository root. Turned into SE_MODS. */
  modpackFile: string;
  /**
   * Image tag to run.
   *
   * Always an immutable `sha-…` tag produced by the build workflow, never
   * `latest`: the point of writing it here is that the deployed version is
   * readable from the repository, and a moving tag would defeat that. Deploying
   * a new build means changing this line.
   */
  imageTag: string;
};

export const SPEC: Spec = {
  project: "space-engineers",
  projectDescription: "Space Engineers dedicated server for the group, run under Wine and managed by Torch.",
  service: "server",
  serviceDescription: "Space Engineers 1 dedicated server. Publishes 27016/udp for players and 8766/udp for Steam.",
  composeFile: "server/docker-compose.yml",
  modpackFile: "server/modpack.txt",
  imageTag: "sha-527ea96",
};
