import { products } from "@/domain/catalog";
import { Storefront } from "@/components/storefront";

export default function HomePage() {
  return <Storefront products={products} />;
}
