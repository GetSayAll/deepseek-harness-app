#!/usr/bin/env node

import { cp, mkdir, readFile, readdir, stat } from 'node:fs/promises'
import { dirname, join, relative, resolve, sep } from 'node:path'
import process from 'node:process'

const EXCLUDED_DIRECTORIES = new Set([
  '.build',
  '.cache',
  '.git',
  'coverage',
  'dist',
  'node_modules',
  'tests',
])

const [repositoryArgument, runtimeArgument] = process.argv.slice(2)
if (repositoryArgument === undefined || runtimeArgument === undefined) {
  throw new Error('usage: complete-runtime-workspace-closure.mjs <repository-root> <runtime-app-root>')
}

const repositoryRoot = resolve(repositoryArgument)
const runtimeRoot = resolve(runtimeArgument)
const runtimeNodeModules = join(runtimeRoot, 'node_modules')
const workspacePackages = await discoverWorkspacePackages(repositoryRoot)
const queue = await discoverInstalledWorkspacePackages(runtimeRoot, workspacePackages)
const visited = new Set()
const copied = []

while (queue.length > 0) {
  const packageName = queue.shift()
  if (packageName === undefined || visited.has(packageName)) continue
  visited.add(packageName)

  const source = workspacePackages.get(packageName)
  if (source === undefined) {
    throw new Error(`runtime references unknown workspace package ${packageName}`)
  }
  const manifest = await readManifest(join(source, 'package.json'))
  for (const dependency of requiredWorkspaceDependencies(manifest)) {
    const dependencySource = workspacePackages.get(dependency)
    if (dependencySource === undefined) continue
    const destination = join(runtimeNodeModules, ...dependency.split('/'))
    if (!(await pathExists(destination))) {
      await copyPublishedPackage(dependencySource, destination)
      copied.push(dependency)
    }
    queue.push(dependency)
  }
}

console.log(`complete-runtime-workspace-closure: added ${copied.length} workspace packages`)
for (const packageName of copied) console.log(`  ${packageName}`)

async function discoverWorkspacePackages(root) {
  const result = new Map()
  for (const directory of ['apps', 'packages', 'vendor', 'native']) {
    await visit(join(root, directory))
  }
  return result

  async function visit(directory) {
    if (!(await pathExists(directory))) return
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (!entry.isDirectory() || EXCLUDED_DIRECTORIES.has(entry.name)) continue
      const child = join(directory, entry.name)
      const manifestPath = join(child, 'package.json')
      if (await pathExists(manifestPath)) {
        const manifest = await readManifest(manifestPath)
        if (typeof manifest.name === 'string' && !manifest.name.startsWith('@fixture/')) {
          if (result.has(manifest.name)) {
            throw new Error(`duplicate workspace package ${manifest.name}`)
          }
          result.set(manifest.name, child)
        }
      }
      await visit(child)
    }
  }
}

async function discoverInstalledWorkspacePackages(root, workspacePackages) {
  const names = []
  const rootManifest = await readManifest(join(root, 'package.json'))
  if (workspacePackages.has(rootManifest.name)) names.push(rootManifest.name)
  const scope = join(root, 'node_modules', '@deepseek-ai')
  if (!(await pathExists(scope))) return names
  for (const entry of await readdir(scope, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue
    const name = `@deepseek-ai/${entry.name}`
    if (workspacePackages.has(name)) names.push(name)
  }
  return names
}

function requiredWorkspaceDependencies(manifest) {
  const optionalPeers = new Set(
    Object.entries(manifest.peerDependenciesMeta ?? {})
      .filter(([, metadata]) => metadata?.optional === true)
      .map(([name]) => name),
  )
  return [
    ...Object.keys(manifest.dependencies ?? {}),
    ...Object.keys(manifest.peerDependencies ?? {}).filter(name => !optionalPeers.has(name)),
  ]
}

async function copyPublishedPackage(source, destination) {
  const manifest = await readManifest(join(source, 'package.json'))
  if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
    throw new Error(`${manifest.name} does not declare a publish files list`)
  }

  const files = await listFiles(source)
  const positivePatterns = manifest.files.filter(pattern => !pattern.startsWith('!'))
  const negativePatterns = manifest.files
    .filter(pattern => pattern.startsWith('!'))
    .map(pattern => pattern.slice(1))
  const selected = files.filter(path =>
    positivePatterns.some(pattern => matchesPublishPattern(path, pattern))
    && !negativePatterns.some(pattern => matchesPublishPattern(path, pattern)),
  )
  if (selected.length === 0) {
    throw new Error(`${manifest.name} has no built files matching its publish files list`)
  }

  await mkdir(destination, { recursive: true })
  await cp(join(source, 'package.json'), join(destination, 'package.json'))
  for (const path of selected) {
    const target = join(destination, path)
    await mkdir(dirname(target), { recursive: true })
    await cp(join(source, path), target)
  }
}

async function listFiles(root) {
  const result = []
  await visit(root)
  return result

  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.isDirectory() && EXCLUDED_DIRECTORIES.has(entry.name)) continue
      const path = join(directory, entry.name)
      if (entry.isDirectory()) await visit(path)
      else if (entry.isFile()) result.push(relative(root, path).split(sep).join('/'))
    }
  }
}

function matchesPublishPattern(path, rawPattern) {
  const pattern = rawPattern.replace(/^\.\//, '').replace(/\/$/, '')
  if (!pattern.includes('*') && !pattern.includes('?')) {
    return path === pattern || path.startsWith(`${pattern}/`)
  }
  let expression = ''
  for (let index = 0; index < pattern.length; index += 1) {
    const character = pattern[index]
    if (character === '*' && pattern[index + 1] === '*') {
      if (pattern[index + 2] === '/') {
        expression += '(?:.*/)?'
        index += 2
      } else {
        expression += '.*'
        index += 1
      }
    } else if (character === '*') {
      expression += '[^/]*'
    } else if (character === '?') {
      expression += '[^/]'
    } else {
      expression += character.replace(/[.+^${}()|[\]\\]/g, '\\$&')
    }
  }
  return new RegExp(`^${expression}$`).test(path)
}

async function readManifest(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'))
  } catch (error) {
    throw new Error(`cannot read package manifest ${path}`, { cause: error })
  }
}

async function pathExists(path) {
  try {
    await stat(path)
    return true
  } catch (error) {
    if (error?.code === 'ENOENT') return false
    throw error
  }
}
