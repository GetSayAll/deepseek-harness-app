# Agent Note: DS Harness App landing site

Status: implemented

English | [中文](2026-08-14-ds-harness-app-landing-site.zh.md)

## Problem

The desktop application needs a public home before the product is ready to download. The existing `website/` application publishes canonical project documentation and includes upstream product naming throughout its generated route tree, so reusing that build for the application domain would mix two brands and make the marketing page depend on documentation projection rules.

## Decision

`website/landing/` is an independent static entry for `dsapp.sayall.app`. It presents only the DS Harness App product name, states that the application remains in development, describes the application advantages, and links visitors to the requested upstream project page and public source repository. It does not replace or alter the VitePress documentation build.

Cloudflare Workers Static Assets serves the directory through `website/landing.wrangler.jsonc`. The site has no application runtime, analytics, persistence, or build dependency; HTML, CSS, and the small navigation/reveal script are the complete production input.

## Alternatives considered

**Replace the VitePress home page.** Rejected because the documentation projector owns that route tree and publishes canonical project material under its existing product identity. A marketing-only replacement would either hide the docs or require brand-specific branching throughout the documentation configuration.

**Create another JavaScript application and bundling pipeline.** Rejected because the first release is one informational page with no client data or application state. A framework and dependency graph would add deployment and maintenance work without providing user-visible capability.

**Wait until the desktop application is downloadable.** Rejected because a stable domain, product positioning, and public progress links are useful before the binary is ready.

## Consequences

The application has a small, separately deployable public entry while canonical docs remain unchanged. The static directory intentionally duplicates no documentation content and must continue to avoid presenting the upstream trademark as the application brand. Future interactive product capabilities need an explicit decision about whether this static entry remains sufficient or becomes a separate application package.
