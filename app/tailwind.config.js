/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        paper:   'rgb(var(--c-paper) / <alpha-value>)',
        surface: 'rgb(var(--c-surface) / <alpha-value>)',
        raised:  'rgb(var(--c-raised) / <alpha-value>)',
        ink:     'rgb(var(--c-ink) / <alpha-value>)',
        ink2:    'rgb(var(--c-ink2) / <alpha-value>)',
        ink3:    'rgb(var(--c-ink3) / <alpha-value>)',
        rule:    'rgb(var(--c-rule) / <alpha-value>)',
        rule2:   'rgb(var(--c-rule2) / <alpha-value>)',
        accent:  'rgb(var(--c-accent) / <alpha-value>)',
        'accent-soft': 'rgb(var(--c-accent-soft) / <alpha-value>)',
        brass:   'rgb(var(--c-brass) / <alpha-value>)',
        'brass-soft': 'rgb(var(--c-brass-soft) / <alpha-value>)',
        oxide:   'rgb(var(--c-oxide) / <alpha-value>)',
        'oxide-soft': 'rgb(var(--c-oxide-soft) / <alpha-value>)',
      },
      fontFamily: {
        sans:  ['"Source Sans 3"', 'system-ui', 'sans-serif'],
        serif: ['"Source Serif 4"', 'Georgia', 'serif'],
        mono:  ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      fontSize: {
        '2xs': ['0.6875rem', { lineHeight: '1rem' }],
      },
      boxShadow: {
        card: '0 1px 2px rgb(0 0 0 / 0.04), 0 8px 24px -18px rgb(0 0 0 / 0.35)',
        pop:  '0 8px 32px -8px rgb(0 0 0 / 0.25)',
      },
    },
  },
  plugins: [],
}
