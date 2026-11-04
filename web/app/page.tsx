'use client';

import React, { useState, useRef, useCallback } from 'react';
import dynamic from 'next/dynamic';
import { SiteNav } from '@/components/SiteNav';
import { SiteFooter } from '@/components/SitePage';
import { VictoryModal } from '@/components/VictoryModal';
import { ConfettiCanvas } from '@/components/ConfettiCanvas';
import type { CatCanvasHandle } from '@/components/CatCanvas';

// Dynamic import with SSR disabled for the client-only canvas
const CatCanvas = dynamic(
  () => import('@/components/CatCanvas').then((mod) => mod.CatCanvas),
  { ssr: false }
);

export default function Home() {
  const [gameWon, setGameWon] = useState(false);

  const canvasHandleRef = useRef<CatCanvasHandle | null>(null);

  const handleVictory = useCallback(() => {
    setGameWon(true);
  }, []);

  const handlePlayAgain = useCallback(() => {
    setGameWon(false);
    canvasHandleRef.current?.scatterHerd();
  }, []);

  return (
    <main className="landing">
      {/* Interactive pixel-art herding canvas */}
      <CatCanvas
        onVictory={handleVictory}
        gameWon={gameWon}
        onRef={(handle) => {
          canvasHandleRef.current = handle;
        }}
      />

      {/* UI Overlay Layer */}
      <div id="ui-layer" inert={gameWon ? true : undefined}>
        {/* Top navigation floats directly on the night sky */}
        <SiteNav />

        {/* Hero copy sits in the sky above the meadow */}
        <section className="hero">
          <span className="sign-badge">iPhone · iPad · Beta</span>
          <h1 className="hero-title">Herdcats</h1>
          <p className="hero-subtitle">Tame your autonomous agents from your pocket.</p>
          <p className="hero-description">
            Herdcats is an iPhone and iPad client for Herdr. It connects to your machine over SSH, to the Herdr TUI or Herdr Core, so you can read agent output, answer a blocked prompt, and send input while you are away from your desk.
          </p>
          <div className="hero-actions">
            <a
              href="https://testflight.apple.com/join/nUr62QY1"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary"
            >
              Join the TestFlight ↗
            </a>
            <span className="hero-hint">or herd the cats into the corral below</span>
          </div>
        </section>

        {/* On mobile the header links collapse into this footer */}
        <div className="landing-footer">
          <SiteFooter />
        </div>
      </div>

      {/* VICTORY CELEBRATION MODAL */}
      <VictoryModal isOpen={gameWon} onPlayAgain={handlePlayAgain} />

      {/* Confetti Canvas for Victory Shower */}
      <ConfettiCanvas active={gameWon} />
    </main>
  );
}
