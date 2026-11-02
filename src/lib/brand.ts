export const APP_NAME = 'FITR MAX'

/** Presentation only: retain identifiers and stored account/history records. */
export function displayBrand(value: string): string {
  return value.replace(/(?<![A-Za-z0-9_./])(?:APEX|FitDee|FITR-D|FITR-MAX)(?![A-Za-z0-9_]|[./][A-Za-z0-9_])/g, APP_NAME)
}
