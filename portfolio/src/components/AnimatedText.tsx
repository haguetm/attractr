import { motion, useScroll, useTransform, type MotionValue } from 'framer-motion';
import { useRef } from 'react';

type AnimatedTextProps = {
  text: string;
  className?: string;
  style?: React.CSSProperties;
};

function Char({ char, progress, range }: { char: string; progress: MotionValue<number>; range: [number, number] }) {
  const opacity = useTransform(progress, range, [0.2, 1]);
  return (
    <span className="relative">
      <span className="invisible">{char}</span>
      <motion.span className="absolute left-0 top-0" style={{ opacity }}>
        {char}
      </motion.span>
    </span>
  );
}

export default function AnimatedText({ text, className, style }: AnimatedTextProps) {
  const ref = useRef<HTMLParagraphElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start 0.8', 'end 0.2'] });

  const total = text.length;
  let index = 0;
  const words = text.split(' ');

  return (
    <p ref={ref} className={className} style={style}>
      {words.map((word, w) => {
        // Keep each word on one line; chars inside still animate one by one.
        const chars = word.split('').map((char) => {
          const start = index / total;
          const range: [number, number] = [start, start + 1 / total];
          index += 1;
          return <Char key={index} char={char} progress={scrollYProgress} range={range} />;
        });
        index += 1; // the space
        return (
          <span key={w} className="inline-block whitespace-nowrap">
            {chars}
            {w < words.length - 1 && ' '}
          </span>
        );
      })}
    </p>
  );
}
