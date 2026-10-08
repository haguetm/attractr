import { motion } from 'framer-motion';
import type { CSSProperties, ElementType, ReactNode } from 'react';

type FadeInProps = {
  children: ReactNode;
  as?: ElementType;
  className?: string;
  style?: CSSProperties;
  delay?: number;
  duration?: number;
  x?: number;
  y?: number;
};

// motion.create() must not run on every render: cache one component per tag.
const motionCache = new Map<ElementType, ElementType>();
function getMotion(tag: ElementType): ElementType {
  let component = motionCache.get(tag);
  if (!component) {
    component = motion.create(tag as never) as ElementType;
    motionCache.set(tag, component);
  }
  return component;
}

export default function FadeIn({
  children,
  as = 'div',
  className,
  style,
  delay = 0,
  duration = 0.7,
  x = 0,
  y = 30,
}: FadeInProps) {
  const MotionTag = getMotion(as);
  return (
    <MotionTag
      className={className}
      style={style}
      initial={{ opacity: 0, x, y }}
      whileInView={{ opacity: 1, x: 0, y: 0 }}
      viewport={{ once: true, margin: '50px', amount: 0 }}
      transition={{ delay, duration, ease: [0.25, 0.1, 0.25, 1] }}
    >
      {children}
    </MotionTag>
  );
}
