Verified reference settings:

- `i_pwm = 4'b1101`
- `i_current = 2'b00`
- `i_sleep = 1'b1`
- HCMS control pins: DATA, CLOCK, REGSEL, NCS, RESET

The serializer initializes `o_ready` and `o_serial_data` to zero. `o_ready` drives the display configuration state machine, so this removes placement-dependent power-up behavior when unrelated logic is added to a design.
