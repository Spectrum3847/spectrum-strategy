// biome-ignore-all lint/suspicious/noArrayIndexKey: the token list is static
import { Lexer } from "marked";
import { type CSSProperties, Fragment, type ReactNode, useMemo } from "react";
import { Link } from "react-router";
import { resolveLink, slugger } from "./docs";

interface Tok {
  type: string;
  raw: string;
  text?: string;
  tokens?: Tok[];
  depth?: number;
  href?: string;
  lang?: string;
  ordered?: boolean;
  start?: number | "";
  items?: Tok[];
  task?: boolean;
  checked?: boolean;
  header?: Tok[];
  rows?: Tok[][];
  align?: string | null;
}

interface Ctx {
  bundled: Set<string>;
  slug: (text: string) => string;
}

const entities: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
};
const decode = (text: string) =>
  text.replace(/&(?:amp|lt|gt|quot|#39);/g, (e) => entities[e] ?? e);

function plain(tokens: Tok[] = []): string {
  return tokens
    .map((t) =>
      t.tokens ? plain(t.tokens) : t.type === "text" ? t.raw : (t.text ?? ""),
    )
    .join("");
}

function inline(tokens: Tok[] = [], ctx: Ctx): ReactNode[] {
  return tokens.map((t, i) => {
    switch (t.type) {
      case "text":
        return (
          <Fragment key={i}>
            {t.tokens ? inline(t.tokens, ctx) : decode(t.raw)}
          </Fragment>
        );
      case "escape":
        return <Fragment key={i}>{t.text}</Fragment>;
      case "strong":
        return <strong key={i}>{inline(t.tokens, ctx)}</strong>;
      case "em":
        return <em key={i}>{inline(t.tokens, ctx)}</em>;
      case "del":
        return <del key={i}>{inline(t.tokens, ctx)}</del>;
      case "codespan":
        return <code key={i}>{t.text}</code>;
      case "br":
        return <br key={i} />;
      case "image":
        return <Fragment key={i}>{t.text}</Fragment>;
      case "link": {
        const target = resolveLink(t.href ?? "", ctx.bundled);
        const children = inline(t.tokens, ctx);
        if (target.kind === "internal") {
          return (
            <Link key={i} to={target.to}>
              {children}
            </Link>
          );
        }
        if (target.kind === "external") {
          return (
            <a
              key={i}
              href={target.href}
              target="_blank"
              rel="noopener noreferrer"
            >
              {children}
            </a>
          );
        }
        return <Fragment key={i}>{children}</Fragment>;
      }
      default:
        return <Fragment key={i}>{decode(t.raw)}</Fragment>;
    }
  });
}

const cellAlign = (align?: string | null): CSSProperties | undefined =>
  align === "left" || align === "right" || align === "center"
    ? { textAlign: align }
    : undefined;

function blocks(tokens: Tok[] = [], ctx: Ctx): ReactNode[] {
  return tokens.map((t, i) => {
    switch (t.type) {
      case "space":
        return null;
      case "heading": {
        const Tag =
          `h${Math.min(Math.max(t.depth ?? 2, 1), 6)}` as `h${1 | 2 | 3 | 4 | 5 | 6}`;
        return (
          <Tag key={i} id={ctx.slug(plain(t.tokens))}>
            {inline(t.tokens, ctx)}
          </Tag>
        );
      }
      case "paragraph":
        return <p key={i}>{inline(t.tokens, ctx)}</p>;
      case "text":
        return <Fragment key={i}>{inline(t.tokens, ctx)}</Fragment>;
      case "code":
        return (
          // biome-ignore lint/a11y/noNoninteractiveTabindex: lets the keyboard scroll a wide block
          <pre key={i} tabIndex={0}>
            <code>{t.text}</code>
          </pre>
        );
      case "blockquote":
        return <blockquote key={i}>{blocks(t.tokens, ctx)}</blockquote>;
      case "hr":
        return <hr key={i} />;
      case "list": {
        const Tag = t.ordered ? "ol" : "ul";
        return (
          <Tag
            key={i}
            start={t.ordered && t.start !== "" ? t.start : undefined}
          >
            {(t.items ?? []).map((item, j) => (
              <li key={j}>
                {item.task && (
                  <input
                    type="checkbox"
                    checked={item.checked === true}
                    disabled
                    readOnly
                    aria-label={item.checked ? "Done" : "Not done"}
                  />
                )}
                {blocks(item.tokens, ctx)}
              </li>
            ))}
          </Tag>
        );
      }
      case "table":
        return (
          // biome-ignore lint/a11y/noNoninteractiveTabindex: lets the keyboard scroll a wide table
          <div key={i} className="doc-table" tabIndex={0}>
            <table>
              <thead>
                <tr>
                  {(t.header ?? []).map((cell, j) => (
                    <th key={j} style={cellAlign(cell.align)}>
                      {inline(cell.tokens, ctx)}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {(t.rows ?? []).map((row, r) => (
                  <tr key={r}>
                    {row.map((cell, j) => (
                      <td key={j} style={cellAlign(cell.align)}>
                        {inline(cell.tokens, ctx)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "html":
        return t.raw.trim().startsWith("<!--") ? null : (
          <p key={i}>{decode(t.raw.trim())}</p>
        );
      default:
        return <p key={i}>{decode(t.raw)}</p>;
    }
  });
}

export function Markdown({
  source,
  bundled,
}: {
  source: string;
  bundled: Set<string>;
}) {
  const content = useMemo(
    () =>
      blocks(Lexer.lex(source) as unknown as Tok[], {
        bundled,
        slug: slugger(),
      }),
    [source, bundled],
  );
  return <div className="doc">{content}</div>;
}
