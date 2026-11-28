import { Link } from "react-router";

export function NotFound() {
  return (
    <>
      <h1>Page not found</h1>
      <Link to="/">Go to Now</Link>
    </>
  );
}
