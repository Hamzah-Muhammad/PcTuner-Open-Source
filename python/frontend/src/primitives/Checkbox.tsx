import "./Checkbox.css";

interface CheckboxProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label?: string;
}

/** Ports the "PrimeCheck" custom ControlTemplate. */
export function Checkbox({ checked, onChange, label }: CheckboxProps) {
  return (
    <span className="checkbox">
      <input
        className="input"
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        // Space toggles a checkbox natively; Enter does not. Added here so a
        // keyboard user working down the list can use either key.
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            onChange(!checked);
          }
        }}
        aria-label={label}
      />
      <span className="box">
        <span className="mark">✓</span>
      </span>
    </span>
  );
}
