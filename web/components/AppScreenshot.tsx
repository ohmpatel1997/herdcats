import { screenshotUrl } from '@/lib/screenshots';
import styles from './AppScreenshot.module.css';

type Screen = 'spaces' | 'timeline-light' | 'timeline-dark' | 'terminal-compose' | 'voice' | 'bridge-setup' | 'approval' | 'ipad-split' | 'duo-split';

// Landscape captures from the iPad Pro 13-inch and the unfolded iPhone Duo.
const wide = { 'ipad-split': [1400, 1050], 'duo-split': [1400, 985] } as const;

export function AppScreenshot({ screen, alt, caption }: { screen: Screen; alt: string; caption: string }) {
  const latest = { spaces: '01-spaces', 'terminal-compose': '09-compose', voice: '10-voice' } as const;
  const id = latest[screen as keyof typeof latest];
  const src = id ? screenshotUrl(id, true) : `/assets/app/${screen}.webp`;
  const size = wide[screen as keyof typeof wide];
  const [width, height] = size ?? (id ? [1320, 2868] : [600, 1304]);
  return (
    <figure className={`${styles.figure}${size ? ` ${styles.wide}` : ''}`}>
      <a href={src} target="_blank" rel="noopener noreferrer" aria-label={`Open full screenshot: ${caption}`}>
        <img src={src} alt={alt} width={width} height={height} loading="lazy" decoding="async" className={styles.image} style={size ? { aspectRatio: `${width} / ${height}` } : undefined} />
      </a>
      <figcaption className={styles.caption}>{caption}</figcaption>
    </figure>
  );
}
