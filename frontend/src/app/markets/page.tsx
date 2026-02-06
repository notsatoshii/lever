'use client';

// Markets index - redirects to home since home IS the markets list
import { redirect } from 'next/navigation';

export default function MarketsIndex() {
  redirect('/');
}
