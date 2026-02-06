/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        'lever-green': '#10B981',
        'lever-red': '#EF4444',
        'lever-dark': '#0f0f0f',
        'lever-gray': '#1a1a1a',
      },
    },
  },
  plugins: [],
}
