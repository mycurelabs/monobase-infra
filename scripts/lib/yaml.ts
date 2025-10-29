/**
 * YAML parsing and validation utilities (shared across all scripts)
 */

import { readFileSync, writeFileSync } from "fs";
import { parse as parseYAML, stringify as stringifyYAML } from "yaml";

/**
 * Parse YAML file
 */
export function parseYamlFile<T = unknown>(filePath: string): T {
  const content = readFileSync(filePath, "utf-8");
  return parseYAML(content) as T;
}

/**
 * Write YAML file
 */
export function writeYamlFile(filePath: string, data: unknown): void {
  const content = stringifyYAML(data, {
    indent: 2,
    lineWidth: 0,
  });
  writeFileSync(filePath, content, "utf-8");
}

/**
 * Parse YAML string
 */
export function parseYamlString<T = unknown>(content: string): T {
  return parseYAML(content) as T;
}

/**
 * Stringify to YAML
 */
export function toYamlString(data: unknown): string {
  return stringifyYAML(data, {
    indent: 2,
    lineWidth: 0,
  });
}
