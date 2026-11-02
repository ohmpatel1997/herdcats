import React, {useEffect, useRef, useState} from 'react';
import {AbsoluteFill, Img, Still, continueRender, delayRender, staticFile} from 'remotion';
import jost600 from './fonts/Jost-600.woff2';
import {drawNightScenery, PALETTE} from '../../../web/lib/scenery.ts';

// Product page header (21:9), search results (3:2), and OG card (1200×630) creative assets.
// Same Moonlit scenery as the website landing page (web/lib/scenery.ts), drawn
// at export resolution so the pixels stay crisp. Text is one short phrase.
const fontFace = `@font-face{font-family:"Jost";font-weight:600;src:url(${jost600}) format("woff2");}`;
const font = '"Jost", Futura, "Century Gothic", system-ui, sans-serif';

function Scenery({width, height, horizon, pixel, moon}) {
  const ref = useRef(null);
  const [handle] = useState(() => delayRender('scenery'));
  useEffect(() => {
    const ctx = ref.current.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    drawNightScenery(ctx, {width, height, horizon, pixel, moon, ground: true, theme: 'dark'});
    continueRender(handle);
  }, []);
  return <canvas ref={ref} width={width} height={height} style={{position: 'absolute', inset: 0}} />;
}

function Phone({source, sw, sh, width, left, top, rotation = 0}) {
  const bezel = width * 0.018;
  const screenWidth = width - bezel * 2;
  const screenHeight = screenWidth * sh / sw;
  const radius = width * 0.115;
  return <div style={{position: 'absolute', left, top, width, height: screenHeight + bezel * 2, padding: bezel,
    boxSizing: 'border-box', borderRadius: radius, background: PALETTE.night800,
    border: `${width * 0.004}px solid ${PALETTE.night900}`, transform: `rotate(${rotation}deg)`, transformOrigin: '50% 20%'}}>
    <div style={{position: 'relative', width: screenWidth, height: screenHeight, overflow: 'hidden',
      borderRadius: radius - bezel, background: '#000', outline: `${width * 0.005}px solid ${PALETTE.night950}`}}>
      <Img src={staticFile(source)} style={{display: 'block', width: screenWidth, height: screenHeight}} />
      <div style={{position: 'absolute', top: screenWidth * 0.029, left: '37%', width: '26%',
        height: screenWidth * 0.075, borderRadius: 100, background: '#000'}} />
    </div>
  </div>;
}

function Tablet({source, sw, sh, width, left, top, rotation = 0}) {
  const bezel = width * 0.016;
  const screenWidth = width - bezel * 2;
  const screenHeight = screenWidth * sh / sw;
  const radius = width * 0.034;
  return <div style={{position: 'absolute', left, top, width, height: screenHeight + bezel * 2, padding: bezel,
    boxSizing: 'border-box', borderRadius: radius, background: PALETTE.night800,
    border: `${width * 0.003}px solid ${PALETTE.night900}`, transform: `rotate(${rotation}deg)`, transformOrigin: '50% 50%'}}>
    <div style={{position: 'relative', width: screenWidth, height: screenHeight, overflow: 'hidden',
      borderRadius: radius - bezel, background: '#000', outline: `${width * 0.004}px solid ${PALETTE.night950}`}}>
      <Img src={staticFile(source)} style={{display: 'block', width: screenWidth, height: screenHeight}} />
    </div>
  </div>;
}

function Wordmark({size}) {
  return <div style={{display: 'flex', alignItems: 'center', gap: size * 0.28}}>
    <Img src={staticFile('logo.png')} style={{width: size * 1.1, height: size * 1.1, borderRadius: '50%',
      border: `${size * 0.04}px solid ${PALETTE.mint200}`, boxSizing: 'border-box'}} />
    <div style={{fontSize: size, fontWeight: 600, letterSpacing: -size * 0.01, lineHeight: 1, color: PALETTE.paper50}}>Herdcats</div>
  </div>;
}

export function ProductHeader({sources, sizes}) {
  const W = 3840, H = 1646;
  return <AbsoluteFill style={{overflow: 'hidden', fontFamily: font}}>
    <style>{fontFace}</style>
    <Scenery width={W} height={H} horizon={H * 0.86} pixel={10} moon={{x: W * 0.64, y: H * 0.3, r: 190}} />
    <div style={{position: 'absolute', left: 240, top: 340, width: 1300}}>
      <Wordmark size={190} />
      <div style={{marginTop: 70, fontSize: 112, fontWeight: 600, lineHeight: 1.1, letterSpacing: -2,
        color: PALETTE.paper50}}>Tame your agents</div>
      <div style={{fontSize: 112, fontWeight: 600, lineHeight: 1.1, letterSpacing: -2,
        color: PALETTE.mint200}}>from your pocket.</div>
    </div>
    <Tablet source={sources.ipad} sw={sizes.ipad.width} sh={sizes.ipad.height} width={1150} left={1480} top={230} />
    <Tablet source={sources.duo} sw={sizes.duo.width} sh={sizes.duo.height} width={1000} left={2110} top={640} />
    <Phone source={sources.phone} sw={sizes.phone.width} sh={sizes.phone.height} width={560} left={3120} top={300} />
  </AbsoluteFill>;
}

export function SearchResult({sources, sizes}) {
  const W = 3840, H = 2560;
  return <AbsoluteFill style={{overflow: 'hidden', fontFamily: font}}>
    <style>{fontFace}</style>
    <Scenery width={W} height={H} horizon={H * 0.9} pixel={10} moon={{x: W * 0.84, y: H * 0.2, r: 210}} />
    <div style={{position: 'absolute', left: 0, right: 0, top: 220, textAlign: 'center', fontSize: 190,
      fontWeight: 600, lineHeight: 1.1, letterSpacing: -3, color: PALETTE.paper50}}>
      <div>Your AI agents,</div>
      <div style={{color: PALETTE.mint200}}>in your pocket.</div>
    </div>
    <Tablet source={sources.ipad} sw={sizes.ipad.width} sh={sizes.ipad.height} width={1400} left={100} top={1080} rotation={-3} />
    <Tablet source={sources.duo} sw={sizes.duo.width} sh={sizes.duo.height} width={1250} left={2410} top={1260} rotation={3} />
    <Phone source={sources.phone} sw={sizes.phone.width} sh={sizes.phone.height} width={820} left={1510} top={900} />
  </AbsoluteFill>;
}

export function OgCard({sources, sizes}) {
  const W = 1200, H = 630;
  return <AbsoluteFill style={{overflow: 'hidden', fontFamily: font}}>
    <style>{fontFace}</style>
    <Scenery width={W} height={H} horizon={H * 0.88} pixel={6} moon={{x: W * 0.78, y: H * 0.28, r: 70}} />
    <div style={{position: 'absolute', left: 96, right: 96, top: 0, bottom: 0,
      display: 'flex', flexDirection: 'column', justifyContent: 'center'}}>
      <Wordmark size={72} />
      <div style={{marginTop: 28, fontSize: 42, fontWeight: 600, lineHeight: 1.2, letterSpacing: -1,
        color: PALETTE.paper50}}>Native iPhone &amp; iPad</div>
      <div style={{fontSize: 42, fontWeight: 600, lineHeight: 1.2, letterSpacing: -1,
        color: PALETTE.mint200}}>client for Herdr</div>
    </div>
    <Tablet source={sources.ipad} sw={sizes.ipad.width} sh={sizes.ipad.height} width={320} left={560} top={290} />
    <Tablet source={sources.duo} sw={sizes.duo.width} sh={sizes.duo.height} width={290} left={750} top={420} />
    <Phone source={sources.phone} sw={sizes.phone.width} sh={sizes.phone.height} width={140} left={1040} top={300} />
  </AbsoluteFill>;
}

export function CreativeRoot() {
  const props = {sources: {phone: 'phone.png', ipad: 'ipad.png', duo: 'duo.png'},
    sizes: {phone: {width: 1320, height: 2868}, ipad: {width: 2752, height: 2064}, duo: {width: 2853, height: 2007}}};
  return <>
    <Still id="ProductHeader" component={ProductHeader} width={3840} height={1646} defaultProps={props} />
    <Still id="SearchResult" component={SearchResult} width={3840} height={2560} defaultProps={props} />
    <Still id="OgCard" component={OgCard} width={1200} height={630} defaultProps={props} />
  </>;
}
