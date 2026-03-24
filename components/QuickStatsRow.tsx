import React from 'react';
import QuickStatsCard, { type QuickStatsCardProps } from './QuickStatsCard';

type QuickStatItem = Pick<
  QuickStatsCardProps,
  'label' | 'value' | 'status' | 'icon' | 'trend'
>;

const QUICK_STATS: QuickStatItem[] = [
  {
    label: 'HbA1c',
    value: '8.0%',
    status: 'High',
    icon: 'A1C',
    trend: [7.2, 7.4, 7.7, 8.0],
  },
  {
    label: 'Fasting Glucose',
    value: '260 mg/dL',
    status: 'High',
    icon: 'FG',
    trend: [210, 228, 241, 260],
  },
  {
    label: 'Cholesterol Total',
    value: '195 mg/dL',
    status: 'Normal',
    icon: 'TC',
    trend: [202, 199, 197, 195],
  },
  {
    label: 'Triglycerides',
    value: '184 mg/dL',
    status: 'High',
    icon: 'TG',
    trend: [170, 176, 180, 184],
  },
];

export interface QuickStatsRowProps {
  className?: string;
}

export const QuickStatsRow: React.FC<QuickStatsRowProps> = ({ className = '' }) => {
  return (
    <section className={className}>
      <h2 className="m-0 text-xl leading-7 font-bold text-cyan-600 tracking-[0.2px]">
        Quick Stats
      </h2>

      <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {QUICK_STATS.map((item) => (
          <div key={item.label}>
            <QuickStatsCard
              label={item.label}
              value={item.value}
              status={item.status}
              icon={item.icon}
              trend={item.trend}
            />
          </div>
        ))}
      </div>
    </section>
  );
};

export default QuickStatsRow;
