import React, { type ReactNode, useMemo } from 'react';

export type QuickStatsStatus = 'High' | 'Normal' | 'Low';

export interface QuickStatsCardProps {
  label: string;
  value: string;
  status: QuickStatsStatus;
  icon?: ReactNode | string;
  trend: number[];
  className?: string;
}

const STATUS_STYLES: Record<
  QuickStatsStatus,
  { border: string; badgeBg: string; badgeText: string; line: string }
> = {
  High: {
    border: '#EF4444',
    badgeBg: '#FEF2F2',
    badgeText: '#B91C1C',
    line: '#EF4444',
  },
  Normal: {
    border: '#22C55E',
    badgeBg: '#F0FDF4',
    badgeText: '#15803D',
    line: '#22C55E',
  },
  Low: {
    border: '#F59E0B',
    badgeBg: '#FFFBEB',
    badgeText: '#B45309',
    line: '#F59E0B',
  },
};

export const QuickStatsCard: React.FC<QuickStatsCardProps> = ({
  label,
  value,
  status,
  icon,
  trend,
  className = '',
}) => {
  const style = STATUS_STYLES[status];

  const points = useMemo(() => {
    if (!trend.length) return '';

    const width = 280;
    const height = 44;
    const pad = 4;
    const min = Math.min(...trend);
    const max = Math.max(...trend);
    const xStep = trend.length > 1 ? (width - pad * 2) / (trend.length - 1) : 0;

    return trend
        .map((num, i) => {
          const x = pad + i * xStep;
          const y =
            max === min
              ? height / 2
              : pad + ((max - num) / (max - min)) * (height - pad * 2);
          return `${x},${y}`;
        })
        .join(' ');
  }, [trend]);

  const resolvedIcon = (() => {
    if (React.isValidElement(icon)) return icon;
    if (typeof icon === 'string' && icon.trim().length > 0) {
      return (
        <span
          aria-hidden="true"
          style={{ fontSize: 12, fontWeight: 700, color: '#334155' }}
        >
          {icon}
        </span>
      );
    }
    return (
      <span
        aria-hidden="true"
        style={{
          width: 8,
          height: 8,
          display: 'inline-block',
          borderRadius: 999,
          backgroundColor: '#94A3B8',
        }}
      />
    );
  })();

  return (
    <article
      className={className}
      style={{
        background: '#FFFFFF',
        borderRadius: 12,
        padding: 16,
        borderLeft: `4px solid ${style.border}`,
        boxShadow: '0 4px 14px rgba(15, 23, 42, 0.08)',
      }}
    >
      <header
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 8,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span
            aria-hidden="true"
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: '#F8FAFC',
              border: '1px solid #E2E8F0',
            }}
          >
            {resolvedIcon}
          </span>
          <span style={{ fontSize: 14, fontWeight: 600, color: '#334155' }}>
            {label}
          </span>
        </div>

        <span
          style={{
            fontSize: 11,
            lineHeight: '18px',
            padding: '0 8px',
            borderRadius: 999,
            fontWeight: 700,
            background: style.badgeBg,
            color: style.badgeText,
          }}
        >
          {status}
        </span>
      </header>

      <p
        style={{
          margin: '10px 0 12px 0',
          fontSize: 24,
          lineHeight: '30px',
          fontWeight: 700,
          color: '#0F172A',
        }}
      >
        {value}
      </p>

      <svg
        role="img"
        aria-label={`${label} trend sparkline`}
        width="100%"
        height="44"
        viewBox="0 0 280 44"
        preserveAspectRatio="none"
      >
        <polyline
          fill="none"
          stroke={style.line}
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          points={points || '4,22 276,22'}
        />
      </svg>
    </article>
  );
};

export default QuickStatsCard;
