/**
 * Global Mongoose plugins.
 *
 * `toJsonPlugin` makes every document serialise with the API id conventions
 * (docs/03-API_CONTRACT.md: ids are exposed as `id`, never `_id` / `__v`).
 * It composes with a schema's own toJSON transform, so it can be combined with
 * other options and applying it twice is a no-op. Only `toJSON` is touched:
 * `toObject()` keeps `_id` for internal use.
 *
 * Usage: every model already gets it through `applyToJson()` in
 * src/models/schemaUtils.js (`schema.plugin(toJsonPlugin)` per schema). Do **not** add
 * `mongoose.plugin(toJsonPlugin)` in src/models/index.js: under ES modules the model files
 * are evaluated (and compiled) before index.js' body runs, so a global plugin registered
 * there would come too late. New schemas outside src/models should call `applyToJson()`
 * or `schema.plugin(toJsonPlugin)` before `mongoose.model()`.
 */

const MARK = Symbol.for('familyhub.toJsonPlugin');

function idTransform(_doc, ret) {
  if (ret && typeof ret === 'object') {
    if (ret._id !== undefined && ret._id !== null && ret.id === undefined) ret.id = String(ret._id);
    delete ret._id;
    delete ret.__v;
  }
  return ret;
}
idTransform[MARK] = true;

function compose(existing) {
  if (typeof existing !== 'function') return idTransform;
  if (existing[MARK]) return existing;
  const composed = function transform(doc, ret, options) {
    const out = existing.call(this, doc, ret, options);
    // A transform may return a new object, `undefined` (mutated in place) or `false` (omit).
    if (out === false) return out;
    return idTransform(doc, out === undefined ? ret : out);
  };
  composed[MARK] = true;
  return composed;
}

export function toJsonPlugin(schema) {
  const current = schema.get('toJSON') ?? {};
  schema.set('toJSON', { ...current, versionKey: false, transform: compose(current.transform) });
}

export default toJsonPlugin;
