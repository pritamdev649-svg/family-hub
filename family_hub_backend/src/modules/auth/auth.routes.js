import { Router } from 'express';
import { validate } from '../../lib/validate.js';
import { requireAuth } from '../../middleware/auth.js';
import { authLimiter, createRateLimiter } from '../../middleware/rateLimit.js';
import * as controller from './auth.controller.js';
import {
  changePasswordSchema,
  forgotPasswordSchema,
  loginSchema,
  logoutSchema,
  refreshSchema,
  registerSchema,
  resetPasswordSchema,
  verifyEmailSchema,
} from './auth.schemas.js';

/**
 * `/api/v1/auth` (docs/03-API_CONTRACT.md §4).
 *
 * Public credential endpoints share `authLimiter` (20/min/IP). `/refresh` gets its own, more
 * generous limiter: every signed-in device calls it every 15 min, and many devices can share
 * one carrier-NAT address. Authenticated OTP endpoints are bounded by the OTP rules
 * (5 attempts, 60 s resend cooldown) and the global limiter.
 */
const refreshLimiter = createRateLimiter({ limit: 60, identifier: 'auth-refresh' });

const router = Router();

router.post('/register', authLimiter, validate({ body: registerSchema }), controller.register);
router.post('/login', authLimiter, validate({ body: loginSchema }), controller.login);
router.post('/refresh', refreshLimiter, validate({ body: refreshSchema }), controller.refresh);
router.post('/logout', requireAuth, validate({ body: logoutSchema }), controller.logout);
router.post('/verify-email', requireAuth, validate({ body: verifyEmailSchema }), controller.verifyEmail);
router.post('/resend-verification', requireAuth, controller.resendVerification);
router.post('/forgot-password', authLimiter, validate({ body: forgotPasswordSchema }), controller.forgotPassword);
router.post('/reset-password', authLimiter, validate({ body: resetPasswordSchema }), controller.resetPassword);
router.post('/change-password', requireAuth, validate({ body: changePasswordSchema }), controller.changePassword);
router.get('/me', requireAuth, controller.me);

export default router;
