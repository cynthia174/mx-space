#!/usr/bin/env node
import { execSync } from 'node:child_process'
import {
  appendFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
} from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'

const require = createRequire(import.meta.url)
const {
  dashboard: { repo, version },
} = require('./package.json')

// Keep the bundled dashboard compatible with this Core release.
const url = `https://github.com/${repo}/releases/download/v${version}/release.zip`
;(async () => {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Dashboard download failed: HTTP ${response.status} (${url})`)
  }
  const buffer = await response.arrayBuffer()
  const zipPath = join(process.cwd(), 'admin-release.zip')
  appendFileSync(zipPath, Buffer.from(buffer))

  const files = readdirSync(process.cwd())
  for (const file of files) {
    const stat = statSync(join(process.cwd(), file))
    console.log(
      `${stat.isDirectory() ? 'd' : '-'} ${file} (${stat.size} bytes)`,
    )
  }

  execSync('unzip admin-release.zip -d out', { stdio: 'inherit' })
  renameSync(join(process.cwd(), 'out/dist'), join(process.cwd(), 'out/admin'))
  unlinkSync(zipPath)
  // release.zip > dist > index.html
})().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
