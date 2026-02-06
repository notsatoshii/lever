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
        'lever-green': '#22c55e', // green-500 for consistency
        'lever-red': '#ef4444', // red-500 for consistency
        'lever-blue': '#3b82f6', // blue-500 for accents
        'lever-dark': '#030712', // gray-950
        'lever-gray': '#1f2937', // gray-800
      },
      animation: {
        'in': 'fadeIn 0.3s ease-in-out',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0', transform: 'translateY(-10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
      },
    },
  },
  plugins: [],
}
