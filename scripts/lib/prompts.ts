/**
 * CLI prompts (shared across all scripts)
 */

import * as clack from "@clack/prompts";
import { basename } from "path";

export { clack };

/**
 * Start a spinner with a message
 */
export function startSpinner(message: string) {
  return clack.spinner();
}

/**
 * Prompt for text input
 */
export async function promptText(options: {
  message: string;
  placeholder?: string;
  defaultValue?: string;
  validate?: (value: string) => string | void;
}): Promise<string> {
  const result = await clack.text(options);
  if (clack.isCancel(result)) {
    clack.cancel("Operation cancelled");
    process.exit(0);
  }
  return result;
}

/**
 * Prompt for password input (masked)
 */
export async function promptPassword(options: {
  message: string;
  validate?: (value: string) => string | void;
}): Promise<string> {
  const result = await clack.password(options);
  if (clack.isCancel(result)) {
    clack.cancel("Operation cancelled");
    process.exit(0);
  }
  return result;
}

/**
 * Prompt for confirmation
 */
export async function promptConfirm(options: {
  message: string;
  initialValue?: boolean;
}): Promise<boolean> {
  const result = await clack.confirm(options);
  if (clack.isCancel(result)) {
    clack.cancel("Operation cancelled");
    process.exit(0);
  }
  return result;
}

/**
 * Prompt for selection from a list
 */
export async function promptSelect<T extends string>(options: {
  message: string;
  options: Array<{
    value: T;
    label: string;
    hint?: string;
  }>;
}): Promise<T> {
  const result = await clack.select(options);
  if (clack.isCancel(result)) {
    clack.cancel("Operation cancelled");
    process.exit(0);
  }
  return result as T;
}

/**
 * Prompt for multi-selection from a list
 */
export async function promptMultiSelect<T extends string>(options: {
  message: string;
  options: Array<{
    value: T;
    label: string;
    hint?: string;
  }>;
  required?: boolean;
}): Promise<T[]> {
  const result = await clack.multiselect(options);
  if (clack.isCancel(result)) {
    clack.cancel("Operation cancelled");
    process.exit(0);
  }
  return result as T[];
}

/**
 * Display a note message
 */
export function note(message: string, title?: string) {
  clack.note(message, title);
}

/**
 * Display an intro message
 */
export function intro(title: string) {
  clack.intro(title);
}

/**
 * Display an outro message
 */
export function outro(message: string) {
  clack.outro(message);
}

/**
 * Display a log message
 */
export function log(message: string) {
  clack.log.message(message);
}

/**
 * Display a step message
 */
export function logStep(message: string) {
  clack.log.step(message);
}

/**
 * Display a success message
 */
export function logSuccess(message: string) {
  clack.log.success(message);
}

/**
 * Display a warning message
 */
export function logWarning(message: string) {
  clack.log.warn(message);
}

/**
 * Display an error message
 */
export function logError(message: string) {
  clack.log.error(message);
}

/**
 * Display an info message
 */
export function logInfo(message: string) {
  clack.log.info(message);
}
