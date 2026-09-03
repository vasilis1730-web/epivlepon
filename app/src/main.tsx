import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, HashRouter } from 'react-router-dom'
import App from './App'
import './index.css'

// Γλώσσα εγγράφου: εξασφαλίζει τη σωστή κεφαλαιοποίηση των ελληνικών
// (τα κεφαλαία δεν φέρουν τόνο) ακόμη κι όταν η σελίδα ενσωματώνεται αλλού.
document.documentElement.lang = 'el'

// Θέμα: ακολουθεί το λειτουργικό, με δυνατότητα χειροκίνητης επιλογής.
// Η ανάγνωση προστατεύεται (η αποθήκευση μπορεί να μην είναι διαθέσιμη σε
// ορισμένα περιβάλλοντα, π.χ. ενσωματωμένη προεπισκόπηση).
try {
  const saved = localStorage.getItem('theme')
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
  if (saved === 'dark' || (!saved && prefersDark)) {
    document.documentElement.classList.add('dark')
  }
} catch {
  /* χωρίς αποθήκευση: μένει το φωτεινό θέμα */
}

// Σε αυτόνομη προεπισκόπηση (χωρίς web server) χρησιμοποιείται HashRouter,
// ώστε η πλοήγηση να λειτουργεί χωρίς rewrite διαδρομών.
const Router = import.meta.env.VITE_HASH_ROUTER === '1' ? HashRouter : BrowserRouter

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Router>
      <App />
    </Router>
  </React.StrictMode>,
)
