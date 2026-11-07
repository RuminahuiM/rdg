// Light and dark follow the operating system setting.
import { useEffect, useState } from 'react';
import { webDarkTheme, webLightTheme, type Theme } from '@fluentui/react-components';

const query = '(prefers-color-scheme: dark)';

export function useColorScheme(): 'light' | 'dark' {
  const read = () => (typeof window !== 'undefined' && window.matchMedia?.(query).matches ? 'dark' : 'light');
  const [scheme, setScheme] = useState<'light' | 'dark'>(read);
  useEffect(() => {
    const media = window.matchMedia?.(query);
    if (!media) return undefined;
    const listener = () => setScheme(media.matches ? 'dark' : 'light');
    media.addEventListener('change', listener);
    return () => media.removeEventListener('change', listener);
  }, []);
  return scheme;
}

export function themeFor(scheme: 'light' | 'dark'): Theme {
  return scheme === 'dark' ? webDarkTheme : webLightTheme;
}
