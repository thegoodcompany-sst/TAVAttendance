import { mkdir, readdir, unlink } from "node:fs/promises";
import { join } from "node:path";
export default async function clearScreenshots() {
  const folder = "/workspace/tav-teacher-prompts/screens";
  await mkdir(folder, { recursive: true });
  for (const file of await readdir(folder))
    if (file.endsWith(".png")) await unlink(join(folder, file));
}
