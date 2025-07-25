;; Bridge Safety Monitoring Contract
;; Monitors structural integrity of bridges and tunnels using sensor data

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-BRIDGE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-READING (err u102))
(define-constant ERR-INVALID-THRESHOLD (err u103))

;; Data Variables
(define-data-var next-bridge-id uint u1)
(define-data-var emergency-threshold uint u20)

;; Data Maps
(define-map bridges
  { bridge-id: uint }
  {
    name: (string-ascii 50),
    location: (string-ascii 100),
    construction-year: uint,
    last-inspection: uint,
    safety-score: uint,
    status: (string-ascii 20),
    total-readings: uint
  }
)

(define-map sensor-readings
  { bridge-id: uint, reading-id: uint }
  {
    timestamp: uint,
    vibration-level: uint,
    stress-level: uint,
    temperature: uint,
    recorded-by: principal
  }
)

(define-map bridge-alerts
  { bridge-id: uint, alert-id: uint }
  {
    alert-type: (string-ascii 30),
    severity: uint,
    message: (string-ascii 200),
    timestamp: uint,
    resolved: bool
  }
)

;; Public Functions

;; Register a new bridge in the system
(define-public (register-bridge (name (string-ascii 50)) (location (string-ascii 100)) (construction-year uint))
  (let ((bridge-id (var-get next-bridge-id)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> construction-year u1900) ERR-INVALID-READING)
    (map-set bridges
      { bridge-id: bridge-id }
      {
        name: name,
        location: location,
        construction-year: construction-year,
        last-inspection: block-height,
        safety-score: u100,
        status: "ACTIVE",
        total-readings: u0
      }
    )
    (var-set next-bridge-id (+ bridge-id u1))
    (ok bridge-id)
  )
)

;; Record sensor reading for a bridge
(define-public (record-sensor-reading (bridge-id uint) (vibration uint) (stress uint) (temperature uint))
  (let (
    (bridge (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-BRIDGE-NOT-FOUND))
    (reading-id (+ (get total-readings bridge) u1))
    (safety-score (calculate-safety-score vibration stress temperature))
  )
    (asserts! (< vibration u100) ERR-INVALID-READING)
    (asserts! (< stress u100) ERR-INVALID-READING)
    (asserts! (< temperature u200) ERR-INVALID-READING)

    ;; Record the sensor reading
    (map-set sensor-readings
      { bridge-id: bridge-id, reading-id: reading-id }
      {
        timestamp: block-height,
        vibration-level: vibration,
        stress-level: stress,
        temperature: temperature,
        recorded-by: tx-sender
      }
    )

    ;; Update bridge data
    (map-set bridges
      { bridge-id: bridge-id }
      (merge bridge {
        safety-score: safety-score,
        total-readings: reading-id,
        last-inspection: block-height,
        status: (if (< safety-score (var-get emergency-threshold)) "CRITICAL" "ACTIVE")
      })
    )

    ;; Generate alert if safety score is critical and return reading-id
    (if (< safety-score (var-get emergency-threshold))
      (match (generate-alert bridge-id "SAFETY_CRITICAL" u5 "Bridge safety score below emergency threshold")
        success (ok reading-id)
        error (err error)
      )
      (ok reading-id)
    )
  )
)

;; Generate maintenance alert
(define-public (generate-alert (bridge-id uint) (alert-type (string-ascii 30)) (severity uint) (message (string-ascii 200)))
  (let (
    (bridge (unwrap! (map-get? bridges { bridge-id: bridge-id }) ERR-BRIDGE-NOT-FOUND))
    (alert-id (+ (get total-readings bridge) u1))
  )
    (asserts! (<= severity u5) ERR-INVALID-READING)
    (map-set bridge-alerts
      { bridge-id: bridge-id, alert-id: alert-id }
      {
        alert-type: alert-type,
        severity: severity,
        message: message,
        timestamp: block-height,
        resolved: false
      }
    )
    (ok alert-id)
  )
)

;; Update emergency threshold
(define-public (update-emergency-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-threshold u0) ERR-INVALID-THRESHOLD)
    (asserts! (< new-threshold u100) ERR-INVALID-THRESHOLD)
    (var-set emergency-threshold new-threshold)
    (ok true)
  )
)

;; Read-only Functions

;; Get bridge information
(define-read-only (get-bridge-info (bridge-id uint))
  (map-get? bridges { bridge-id: bridge-id })
)

;; Get sensor reading
(define-read-only (get-sensor-reading (bridge-id uint) (reading-id uint))
  (map-get? sensor-readings { bridge-id: bridge-id, reading-id: reading-id })
)

;; Get bridge alert
(define-read-only (get-bridge-alert (bridge-id uint) (alert-id uint))
  (map-get? bridge-alerts { bridge-id: bridge-id, alert-id: alert-id })
)

;; Calculate safety score based on sensor readings
(define-read-only (calculate-safety-score (vibration uint) (stress uint) (temperature uint))
  (let (
    (vibration-score (if (< vibration u30) u100 (if (< vibration u60) u70 u30)))
    (stress-score (if (< stress u40) u100 (if (< stress u70) u60 u20)))
    (temp-score (if (< temperature u80) u100 (if (< temperature u120) u80 u50)))
  )
    (/ (+ vibration-score stress-score temp-score) u3)
  )
)

;; Get current emergency threshold
(define-read-only (get-emergency-threshold)
  (var-get emergency-threshold)
)
